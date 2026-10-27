'use strict';

const jwt = require('jsonwebtoken');
const request = require('supertest');
const { app, registerUser, cleanup } = require('./helpers');

afterAll(cleanup);

const auth = (user) => ({ Authorization: `Bearer ${user.accessToken}` });

describe('task authentication', () => {
  test('rejects requests without a token', async () => {
    const response = await request(app).get('/api/v1/tasks');
    expect(response.status).toBe(401);
    expect(response.body.error.code).toBe('UNAUTHENTICATED');
  });

  test('rejects a token signed with the wrong secret', async () => {
    const forged = jwt.sign({ sub: 'someone', type: 'access' }, 'x'.repeat(40), {
      issuer: 'task-manager-api',
      audience: 'task-manager-client',
    });
    const response = await request(app).get('/api/v1/tasks')
      .set('Authorization', `Bearer ${forged}`);
    expect(response.status).toBe(401);
  });

  test('rejects a refresh token used as an access token', async () => {
    const user = await registerUser('wrongtype');
    const response = await request(app).get('/api/v1/tasks')
      .set('Authorization', `Bearer ${user.refreshToken}`);
    expect(response.status).toBe(401);
  });
});

describe('task CRUD', () => {
  test('creates, lists, updates and deletes a task', async () => {
    const user = await registerUser('crud');

    const created = await request(app).post('/api/v1/tasks').set(auth(user))
      .send({ title: '  Review API security ', description: 'Check ownership and validation' });
    expect(created.status).toBe(201);
    expect(created.body.item.title).toBe('Review API security');
    expect(created.body.item.ownerId).toBeDefined();

    const list = await request(app).get('/api/v1/tasks?page=1&limit=20').set(auth(user));
    expect(list.status).toBe(200);
    expect(list.body.items).toHaveLength(1);
    expect(list.body.page).toBe(1);

    const updated = await request(app).patch(`/api/v1/tasks/${created.body.item.id}`)
      .set(auth(user)).send({ completed: true });
    expect(updated.status).toBe(200);
    expect(updated.body.item.completed).toBe(true);

    const removed = await request(app).delete(`/api/v1/tasks/${created.body.item.id}`).set(auth(user));
    expect(removed.status).toBe(204);

    const empty = await request(app).get('/api/v1/tasks').set(auth(user));
    expect(empty.body.items).toHaveLength(0);
  });

  test('ignores a client-supplied ownerId', async () => {
    const owner = await registerUser('spoof-owner');
    const victim = await registerUser('spoof-victim');
    const victimId = JSON.parse(Buffer.from(victim.accessToken.split('.')[1], 'base64url')).sub;

    const created = await request(app).post('/api/v1/tasks').set(auth(owner))
      .send({ title: 'Mine', ownerId: victimId });
    expect(created.status).toBe(201);
    expect(created.body.item.ownerId).not.toBe(victimId);

    const victimList = await request(app).get('/api/v1/tasks').set(auth(victim));
    expect(victimList.body.items).toHaveLength(0);
  });

  test('validates task payloads, pagination bounds and IDs', async () => {
    const user = await registerUser('validation');
    const emptyTitle = await request(app).post('/api/v1/tasks').set(auth(user)).send({ title: '   ' });
    expect(emptyTitle.status).toBe(400);

    const emptyPatch = await request(app).patch('/api/v1/tasks/cabcdefghijklmnopqrstuvwx')
      .set(auth(user)).send({});
    expect(emptyPatch.status).toBe(400);

    const tooLarge = await request(app).get('/api/v1/tasks?limit=1000').set(auth(user));
    expect(tooLarge.status).toBe(400);

    const badId = await request(app).delete(`/api/v1/tasks/${encodeURIComponent("1' OR '1'='1")}`).set(auth(user));
    expect(badId.status).toBe(400);
    expect(badId.body.error.code).toBe('VALIDATION_ERROR');
  });
});

describe('cross-user authorization (IDOR)', () => {
  test('User A cannot read, update or delete User B task', async () => {
    const userA = await registerUser('alice');
    const userB = await registerUser('bob');

    const created = await request(app).post('/api/v1/tasks').set(auth(userB))
      .send({ title: 'Private task of B' });
    const taskId = created.body.item.id;

    const read = await request(app).get(`/api/v1/tasks/${taskId}`).set(auth(userA));
    expect(read.status).toBe(404);

    const list = await request(app).get('/api/v1/tasks').set(auth(userA));
    expect(list.body.items.find((t) => t.id === taskId)).toBeUndefined();

    const update = await request(app).patch(`/api/v1/tasks/${taskId}`).set(auth(userA))
      .send({ title: 'hacked' });
    expect(update.status).toBe(404);

    const remove = await request(app).delete(`/api/v1/tasks/${taskId}`).set(auth(userA));
    expect(remove.status).toBe(404);

    const stillThere = await request(app).get(`/api/v1/tasks/${taskId}`).set(auth(userB));
    expect(stillThere.status).toBe(200);
    expect(stillThere.body.item.title).toBe('Private task of B');
  });
});
