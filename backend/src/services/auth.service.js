'use strict';

const bcrypt = require('bcrypt');
const crypto = require('node:crypto');
const { prisma } = require('../repositories/prisma');
const userRepository = require('../repositories/user.repository');
const tokenRepository = require('../repositories/refresh-token.repository');
const { createAccessToken, createRefreshToken, hashToken } = require('../utils/tokens');

const BCRYPT_COST = 12;
const REFRESH_TTL_MS = 7 * 24 * 60 * 60 * 1000;
// Compared against when the email is unknown so response timing does not reveal accounts.
const DUMMY_PASSWORD_HASH = bcrypt.hashSync(crypto.randomBytes(16).toString('hex'), BCRYPT_COST);

/** Creates a safe authentication error with an HTTP status and code. */
function authError(message = 'Authentication required.') {
  const error = new Error(message);
  error.status = 401;
  error.code = 'UNAUTHENTICATED';
  return error;
}

/** Registers a user with a one-way password hash. */
async function register({ email, password }) {
  const passwordHash = await bcrypt.hash(password, BCRYPT_COST);
  try {
    const user = await userRepository.createUser({ email, passwordHash });
    return issueTokens(user.id, crypto.randomUUID());
  } catch (error) {
    if (error.code === 'P2002') {
      const conflict = new Error('An account with this email already exists.');
      conflict.status = 409;
      conflict.code = 'CONFLICT';
      throw conflict;
    }
    throw error;
  }
}

/** Authenticates credentials with a generic failure response. */
async function login({ email, password }) {
  const user = await userRepository.findByEmail(email);
  const passwordHash = user?.passwordHash || DUMMY_PASSWORD_HASH;
  const matches = await bcrypt.compare(password, passwordHash);
  if (!user || !matches) throw authError('Invalid email or password.');
  return issueTokens(user.id, crypto.randomUUID());
}

/** Issues an access/refresh pair and persists only the refresh-token hash. */
async function issueTokens(userId, familyId, db = prisma) {
  const refreshToken = createRefreshToken();
  const record = await tokenRepository.createToken({
    userId,
    tokenHash: hashToken(refreshToken),
    familyId,
    expiresAt: new Date(Date.now() + REFRESH_TTL_MS),
  }, db);
  return {
    accessToken: createAccessToken(userId),
    refreshToken,
    expiresIn: 600,
    recordId: record.id,
  };
}

/** Removes internal fields before tokens are returned to clients. */
function publicTokens({ accessToken, refreshToken, expiresIn }) {
  return { accessToken, refreshToken, expiresIn };
}

/** Rotates a refresh token transactionally and detects reuse of revoked tokens. */
async function refresh(refreshToken) {
  const outcome = await prisma.$transaction(async (tx) => {
    const record = await tokenRepository.findByHash(hashToken(refreshToken), tx);
    if (!record || record.expiresAt <= new Date()) return { error: true };
    if (record.revokedAt) {
      await tokenRepository.revokeFamily(record.familyId, tx);
      return { error: true, reuse: true };
    }
    const tokens = await issueTokens(record.userId, record.familyId, tx);
    const revoked = await tokenRepository.revokeToken(record.id, tx, tokens.recordId);
    // A concurrent refresh already consumed this token: treat it as reuse.
    if (revoked.count === 0) throw authError('Refresh token is invalid or expired.');
    return { tokens };
  });
  if (outcome.error) throw authError('Refresh token is invalid or expired.');
  return publicTokens(outcome.tokens);
}

/** Revokes the entire refresh-token family associated with this token. */
async function logout(refreshToken) {
  const record = await tokenRepository.findByHash(hashToken(refreshToken));
  if (record) await tokenRepository.revokeFamily(record.familyId);
}

/** Revokes all active refresh tokens for the authenticated user. */
function logoutAll(userId) {
  return tokenRepository.revokeAllForUser(userId);
}

module.exports = {
  register: async (input) => publicTokens(await register(input)),
  login: async (input) => publicTokens(await login(input)),
  issueTokens,
  refresh,
  logout,
  logoutAll,
};
