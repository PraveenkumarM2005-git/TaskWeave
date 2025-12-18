import 'package:flutter/foundation.dart';
import '../models/task.dart';

class TaskProvider with ChangeNotifier {
  final List<Task> _tasks = [];

  List<Task> get tasks => List.unmodifiable(_tasks);
  List<Task> get completedTasks =>
      _tasks.where((task) => task.isCompleted).toList();
  List<Task> get pendingTasks =>
      _tasks.where((task) => !task.isCompleted).toList();

  Future<void> addTask({
    required String title,
    String? description,
    DateTime? dueDate,
    String? category,
    String priority = 'medium',
    bool isCompleted = false,
  }) async {
    final task = Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: description,
      dueDate: dueDate,
      category: category,
      priority: priority,
      isCompleted: isCompleted,
      createdAt: DateTime.now(),
    );

    _tasks.add(task);
    notifyListeners();
  }

  void toggleTaskStatus(String taskId) {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index != -1) {
      final task = _tasks[index];
      _tasks[index] = Task(
        id: task.id,
        title: task.title,
        description: task.description,
        dueDate: task.dueDate,
        isCompleted: !task.isCompleted,
        category: task.category,
        priority: task.priority,
      );
      notifyListeners();
    }
  }

  void deleteTask(String taskId) {
    _tasks.removeWhere((task) => task.id == taskId);
    notifyListeners();
  }

  // For demo purposes, you can add some sample tasks
  void loadSampleTasks() {
    // Clear existing tasks
    _tasks.clear();

    // Add sample tasks using the addTask method
    addTask(
      title: 'Complete project setup',
      description: 'Set up the Flutter project with all necessary dependencies',
      isCompleted: true,
      category: 'Development',
      priority: 'high',
    );

    addTask(
      title: 'Design UI mockups',
      description: 'Create UI mockups for the dashboard and task views',
      dueDate: DateTime.now().add(const Duration(days: 2)),
      category: 'Design',
      priority: 'medium',
    );

    notifyListeners();
  }
}
