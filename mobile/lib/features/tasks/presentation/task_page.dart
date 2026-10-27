/// Main screen listing the signed-in user's tasks.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../domain/task.dart';
import 'task_controller.dart';
import 'task_list_view.dart';

/// Shows tasks with create, edit, toggle, delete, and logout actions.
class TaskPage extends ConsumerWidget {
  /// Creates the task page.
  const TaskPage({super.key});

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    Task? task,
  }) async {
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => _TaskDialog(task: task),
    );
    if (result == null || !context.mounted) return;
    final controller = ref.read(taskControllerProvider.notifier);
    await _run(
      context,
      () => task == null
          ? controller.add(result.$1, result.$2)
          : controller.edit(task, result.$1, result.$2),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Task task,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('"${task.title}" will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(
      context,
      () => ref.read(taskControllerProvider.notifier).delete(task),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(taskControllerProvider);
    final controller = ref.read(taskControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My tasks'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: controller.load,
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.load,
        child: TaskListView(
          loading: state.loading,
          tasks: state.tasks,
          errorMessage: state.errorMessage,
          onRetry: controller.load,
          onToggle: (task) => _run(context, () => controller.toggle(task)),
          onDelete: (task) => _confirmDelete(context, ref, task),
          onEdit: (task) => _openEditor(context, ref, task: task),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-task'),
        onPressed: () => _openEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add task'),
      ),
    );
  }
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog({this.task});

  final Task? task;

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.task?.title);
  late final _description =
      TextEditingController(text: widget.task?.description);

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.task == null ? 'New task' : 'Edit task'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('task-title'),
              controller: _title,
              autofocus: true,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Title is required.'
                  : null,
            ),
            TextFormField(
              key: const Key('task-description'),
              controller: _description,
              maxLength: 2000,
              maxLines: 3,
              minLines: 1,
              decoration:
                  const InputDecoration(labelText: 'Description (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('save-task'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, (_title.text, _description.text));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
