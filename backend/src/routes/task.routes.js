'use strict';

const express = require('express');
const { requireAuth } = require('../middleware/auth.middleware');
const { validate } = require('../middleware/validate.middleware');
const {
  createTaskSchema,
  updateTaskSchema,
  listTasksSchema,
  taskIdParamsSchema,
} = require('../schemas/task.schema');
const controller = require('../controllers/task.controller');
const { asyncRoute } = require('../utils/async-route');

const router = express.Router();
const validateId = validate(taskIdParamsSchema, 'params');

router.use(requireAuth);

router.get('/', validate(listTasksSchema, 'query'), asyncRoute(controller.list));
router.post('/', validate(createTaskSchema, 'body'), asyncRoute(controller.create));
router.get('/:taskId', validateId, asyncRoute(controller.get));
router.patch('/:taskId', validateId, validate(updateTaskSchema, 'body'), asyncRoute(controller.update));
router.delete('/:taskId', validateId, asyncRoute(controller.remove));

module.exports = router;
