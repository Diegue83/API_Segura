'use strict';

const crypto = require('node:crypto');
const request = require('supertest');
const { app } = require('../src/app');
const { prisma } = require('../src/repositories/prisma');

const PASSWORD = 'a-long-test-password';

/** Returns a unique test email address. */
function uniqueEmail(prefix = 'user') {
  return `${prefix}-${crypto.randomUUID()}@example.test`;
}

/** Registers a fresh account and returns its credentials and tokens. */
async function registerUser(prefix) {
  const email = uniqueEmail(prefix);
  const response = await request(app).post('/api/v1/auth/register')
    .send({ email, password: PASSWORD });
  expect(response.status).toBe(201);
  return { email, password: PASSWORD, ...response.body };
}

/** Removes every account created by the test suite. */
async function cleanup() {
  await prisma.user.deleteMany({ where: { email: { endsWith: '@example.test' } } });
  await prisma.$disconnect();
}

module.exports = { app, prisma, PASSWORD, uniqueEmail, registerUser, cleanup };
