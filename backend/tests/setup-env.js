'use strict';

// Tests always run against the isolated test database defined in .env.test.
require('dotenv').config({ path: require('node:path').join(__dirname, '..', '.env.test'), quiet: true, override: true });
