import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_service.dart';
import 'task_provider.dart';

class ChatProvider with ChangeNotifier {
  final ChatService _chatService = ChatService();
  final List<Message> _messages = [];
  bool _isLoading = false;
  String? _error;

  List<Message> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get error => _error;

  void addMessage(Message message) {
    _messages.add(message);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> sendMessage(String text, BuildContext context) async {
    if (text.trim().isEmpty) return;

    final userMessage = Message(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    addMessage(userMessage);
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final chatHistory =
          _messages
              .where((msg) => !msg.isError)
              .map(
                (msg) => {
                  'role': msg.isUser ? 'user' : 'assistant',
                  'content': msg.text,
                },
              )
              .toList();

      final response = await _chatService.sendMessage(text, chatHistory);

      if (response['isTask'] == true) {
        // Handle task creation
        final taskData = response['taskData'];
        final taskProvider = Provider.of<TaskProvider>(context, listen: false);

        await taskProvider.addTask(
          title: taskData['title']?.toString() ?? 'New Task',
          description: taskData['description']?.toString(),
          dueDate:
              taskData['dueDate'] != null
                  ? DateTime.tryParse(taskData['dueDate'])
                  : null,
          priority:
              (taskData['priority']?.toString() ?? 'medium').toLowerCase(),
          category: taskData['category']?.toString(),
        );

        // Add a confirmation message
        final taskTitle = taskData['title']?.toString() ?? 'New Task';
        final confirmationMessage = Message(
          text: '✅ Task "$taskTitle" has been added to your tasks!',
          isUser: false,
          timestamp: DateTime.now(),
        );
        addMessage(confirmationMessage);
      } else {
        // Normal chat response
        final aiMessage = Message(
          text: response['message'],
          isUser: false,
          timestamp: DateTime.now(),
        );
        addMessage(aiMessage);
      }
    } catch (e, stackTrace) {
      print('Error in sendMessage: $e');
      print('Stack trace: $stackTrace');

      _error = 'Failed to get response from AI';
      addMessage(
        Message(
          text: 'Sorry, I encountered an error. Please try again.',
          isUser: false,
          timestamp: DateTime.now(),
          isError: true,
        ),
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _messages.clear();
    _error = null;
    _isLoading = false;
    super.dispose();
  }
}

class Message {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;

  Message({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'time': timestamp.toIso8601String(),
    'isError': isError,
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    text: json['text'],
    isUser: json['isUser'],
    timestamp: DateTime.parse(json['time']),
    isError: json['isError'] ?? false,
  );
}
