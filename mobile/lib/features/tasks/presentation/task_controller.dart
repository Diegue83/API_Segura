/// Holds task-list state outside the widget tree.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../domain/task.dart';

/// Immutable snapshot of the task list.
class TaskState {
  /// Creates a task state.
  const TaskState({
    this.loading = false,
    this.tasks = const [],
    this.errorMessage,
  });

  /// Whether tasks are being loaded.
  final bool loading;

  /// Loaded tasks.
  final List<Task> tasks;

  /// Safe error message from the last failed load.
  final String? errorMessage;
}

/// Loads and mutates the signed-in user's tasks.
class TaskController extends AutoDisposeNotifier<TaskState> {
  @override
  TaskState build() {
    Future.microtask(load);
    return const TaskState(loading: true);
  }

  /// Loads the first page of tasks.
  Future<void> load() async {
    state = TaskState(loading: true, tasks: state.tasks);
    try {
      final tasks = await ref.read(taskRepositoryProvider).list();
      state = TaskState(tasks: tasks);
    } catch (error) {
      state = TaskState(errorMessage: error.toString());
    }
  }

  /// Creates a task and prepends it to the list.
  Future<void> add(String title, String? description) async {
    final task = await ref.read(taskRepositoryProvider).create(title, description);
    state = TaskState(tasks: [task, ...state.tasks]);
  }

  /// Edits a task's title and description.
  Future<void> edit(Task task, String title, String? description) async {
    final updated =
        await ref.read(taskRepositoryProvider).edit(task, title, description);
    _replace(updated);
  }

  /// Toggles a task's completion state.
  Future<void> toggle(Task task) async {
    final updated = await ref
        .read(taskRepositoryProvider)
        .setCompleted(task, !task.completed);
    _replace(updated);
  }

  /// Deletes a task.
  Future<void> delete(Task task) async {
    await ref.read(taskRepositoryProvider).delete(task.id);
    state = TaskState(
      tasks: state.tasks.where((t) => t.id != task.id).toList(),
    );
  }

  void _replace(Task updated) {
    state = TaskState(
      tasks: [
        for (final t in state.tasks) t.id == updated.id ? updated : t,
      ],
    );
  }
}

/// Task list state for the signed-in user.
final taskControllerProvider =
    NotifierProvider.autoDispose<TaskController, TaskState>(TaskController.new);
