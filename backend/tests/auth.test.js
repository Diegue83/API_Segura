'use strict';

const request = require('supertest');
const { app, prisma, PASSWORD, uniqueEmail, registerUser, cleanup } = require('./helpers');
const { hashToken } = require('../src/utils/tokens');

afterAll(cleanup);

describe('registration and login', () => {
  test('registers a user and stores only a bcrypt hash of the password', async () => {
    const user = await registerUser('register');
    expect(typeof user.accessToken).toBe('string');
    expect(typeof user.refreshToken).toBe('string');
    expect(user.expiresIn).toBe(600);
    expect(user.recordId).toBeUndefined();

    const stored = await prisma.user.findUnique({ where: { email: user.email } });
    expect(stored.passwordHash).not.toBe(PASSWORD);
    expect(stored.passwordHash).toMatch(/^\$2b\$12\$/);
  });

  test('rejects a duplicate email with 409', async () => {
    const user = await registerUser('dup');
    const response = await request(app).post('/api/v1/auth/register')
      .send({ email: user.email, password: PASSWORD });
    expect(response.status).toBe(409);
    expect(response.body.error.code).toBe('CONFLICT');
  });

  test('rejects invalid input with a 400 validation error', async () => {
    const response = await request(app).post('/api/v1/auth/register')
      .send({ email: 'not-an-email', password: 'short' });
    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe('VALIDATION_ERROR');
    const fields = response.body.error.details.map((d) => d.field);
    expect(fields).toEqual(expect.arrayContaining(['email', 'password']));
  });

  test('logs in with valid credentials', async () => {
    const user = await registerUser('login');
    const response = await request(app).post('/api/v1/auth/login')
      .send({ email: user.email.toUpperCase(), password: PASSWORD });
    expect(response.status).toBe(200);
    expect(response.body.accessToken).toBeDefined();
  });

  test('uses the same generic message for a wrong password and an unknown email', async () => {
    const user = await registerUser('generic');
    const wrongPassword = await request(app).post('/api/v1/auth/login')
      .send({ email: user.email, password: 'wrong-password-123' });
    const unknownEmail = await request(app).post('/api/v1/auth/login')
      .send({ email: uniqueEmail('nobody'), password: 'wrong-password-123' });
    expect(wrongPassword.status).toBe(401);
    expect(unknownEmail.status).toBe(401);
    expect(wrongPassword.body).toEqual(unknownEmail.body);
  });

  test('rejects malformed JSON with a safe error', async () => {
    const response = await request(app).post('/api/v1/auth/login')
      .set('Content-Type', 'application/json')
      .send('{"email":');
    expect(response.status).toBe(400);
    expect(JSON.stringify(response.body)).not.toMatch(/SyntaxError|at .*\.js/);
  });
});

describe('refresh-token lifecycle', () => {
  test('stores only the SHA-256 hash of refresh tokens', async () => {
    const user = await registerUser('hash');
    const raw = await prisma.refreshToken.findUnique({ where: { tokenHash: user.refreshToken } });
    const hashed = await prisma.refreshToken.findUnique({ where: { tokenHash: hashToken(user.refreshToken) } });
    expect(raw).toBeNull();
    expect(hashed).not.toBeNull();
  });

  test('rotation returns a different refresh token', async () => {
    const initial = await registerUser('rotate');
    const response = await request(app).post('/api/v1/auth/refresh')
      .send({ refreshToken: initial.refreshToken });
    expect(response.status).toBe(200);
    expect(response.body.refreshToken).not.toBe(initial.refreshToken);
  });

  test('reuse of an old token revokes the newer token family token', async () => {
    const initial = await registerUser('reuse');
    const rotated = await request(app).post('/api/v1/auth/refresh')
      .send({ refreshToken: initial.refreshToken });
    expect(rotated.status).toBe(200);

    const reuse = await request(app).post('/api/v1/auth/refresh')
      .send({ refreshToken: initial.refreshToken });
    expect(reuse.status).toBe(401);

    const newer = await request(app).post('/api/v1/auth/refresh')
      .send({ refreshToken: rotated.body.refreshToken });
    expect(newer.status).toBe(401);
  });

  test('logout makes the refresh token unusable', async () => {
    const tokens = await registerUser('logout');
    const logout = await request(app).post('/api/v1/auth/logout')
      .send({ refreshToken: tokens.refreshToken });
    expect(logout.status).toBe(204);

    const refresh = await request(app).post('/api/v1/auth/refresh')
      .send({ refreshToken: tokens.refreshToken });
    expect(refresh.status).toBe(401);
  });

  test('logout-all revokes refresh tokens from every session', async () => {
    const user = await registerUser('logoutall');
    const second = await request(app).post('/api/v1/auth/login')
      .send({ email: user.email, password: PASSWORD });

    const logoutAll = await request(app).post('/api/v1/auth/logout-all')
      .set('Authorization', `Bearer ${user.accessToken}`);
    expect(logoutAll.status).toBe(204);

    for (const refreshToken of [user.refreshToken, second.body.refreshToken]) {
      const response = await request(app).post('/api/v1/auth/refresh').send({ refreshToken });
      expect(response.status).toBe(401);
    }
  });
});
