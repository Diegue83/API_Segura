'use strict';

const { PrismaClient } = require('@prisma/client');

/** Shared Prisma client used by every repository. */
const prisma = new PrismaClient();

module.exports = { prisma };
