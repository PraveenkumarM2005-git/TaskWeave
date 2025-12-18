import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ChatService {
  static final String? _apiKey = dotenv.env['OPENROUTER_API_KEY'];
  static const String _apiUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const String _siteUrl = 'http://localhost:8080';
  static const String _appName = 'TaskWeave App';

  Future<Map<String, dynamic>> sendMessage(
    String message,
    List<Map<String, String>> chatHistory,
  ) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      const errorMsg =
          'OpenRouter API key is not configured. Please check your .env file';
      print(errorMsg);
      throw Exception(errorMsg);
    }

    print('Using OpenRouter API key: ${_apiKey!.substring(0, 5)}...');
    print('Message length: ${message.length}');
    print('Chat history length: ${chatHistory.length}');

    try {
      int maxRetries = 3;
      int retryCount = 0;
      Duration retryDelay = const Duration(seconds: 2);

      while (retryCount < maxRetries) {
        try {
          final headers = <String, String>{
            'Authorization': 'Bearer $_apiKey',
            'HTTP-Referer': _siteUrl,
            'X-Title': _appName,
            'Content-Type': 'application/json',
          };

          const systemPrompt = """
You are a helpful task management assistant. Help users manage their tasks.

When suggesting tasks, format them like this:

[Task Title]
Description: [Brief description]
Due: [Date/Time if specified]
Category: [Category if specified]
Priority: [low/medium/high]

Example:
Buy groceries
Description: Milk, eggs, bread, and fruits
Due: Today 6 PM
Category: Shopping
Priority: high
""";

          final messages = <Map<String, String>>[
            {'role': 'system', 'content': systemPrompt},
            ...chatHistory,
            {'role': 'user', 'content': message},
          ];

          final body = jsonEncode({
            'model': 'gpt-3.5-turbo',
            'messages': messages,
            'temperature': _isTaskCreationIntent(message) ? 0.2 : 0.7,
          });

          print('Sending request to: $_apiUrl');
          print('Request headers: $headers');
          print('Request body length: ${body.length}');

          final response = await http
              .post(Uri.parse(_apiUrl), headers: headers, body: body)
              .timeout(
                const Duration(seconds: 30),
                onTimeout: () {
                  throw TimeoutException('Request timed out after 30 seconds');
                },
              );

          print('Response status: ${response.statusCode}');
          print('Response headers: ${response.headers}');
          print('Response body: ${response.body}');

          if (response.statusCode == 200) {
            try {
              final data = jsonDecode(response.body) as Map<String, dynamic>;

              if (data['choices'] == null ||
                  (data['choices'] as List).isEmpty) {
                throw const FormatException('No choices in API response');
              }

              final choices = data['choices'] as List;
              final firstChoice = choices.first as Map<String, dynamic>;
              final message = firstChoice['message'] as Map<String, dynamic>?;
              final content = message?['content'] as String?;

              if (content == null || content.isEmpty) {
                throw const FormatException('Empty content in API response');
              }

              // Check if the response is a task creation response
              try {
                final taskData = jsonDecode(content) as Map<String, dynamic>;
                if (taskData['isTask'] == true) {
                  return {
                    'isTask': true,
                    'taskData': taskData,
                    'message': 'Task created successfully',
                  };
                }
              } catch (e) {
                // Not a task creation response, continue normally
                print('Not a task creation response: $e');
              }

              return {'isTask': false, 'message': content};
            } on FormatException catch (e, stackTrace) {
              print('Error parsing API response: $e');
              print('Stack trace: $stackTrace');
              print('Response body: ${response.body}');
              rethrow;
            }
          } else if (response.statusCode == 429) {
            retryCount++;
            if (retryCount < maxRetries) {
              print(
                'Rate limited. Retrying in ${retryDelay.inSeconds} seconds... (Attempt ${retryCount + 1}/$maxRetries)',
              );
              await Future.delayed(retryDelay);
              continue;
            }
            throw HttpException(
              'API rate limit exceeded. Please try again later or add your API key.',
              statusCode: response.statusCode,
            );
          } else {
            final errorMsg =
                'API request failed with status ${response.statusCode}: ${response.body}';
            print(errorMsg);
            throw HttpException(
              'API request failed with status ${response.statusCode}',
              statusCode: response.statusCode,
            );
          }
        } on TimeoutException catch (e) {
          final errorMsg = 'Request timed out';
          print('$errorMsg: $e');
          if (retryCount == maxRetries - 1) rethrow;
          retryCount++;
          continue;
        } on http.ClientException catch (e) {
          final errorMsg = 'Network error: ${e.message}';
          print(errorMsg);
          if (retryCount == maxRetries - 1) rethrow;
          retryCount++;
          continue;
        }
      }
      throw Exception('Failed after $maxRetries attempts');
    } catch (e, stackTrace) {
      print('Unexpected error: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  bool _isTaskCreationIntent(String message) {
    final lowerMessage = message.toLowerCase();
    return lowerMessage.contains('add task') ||
        lowerMessage.contains('create task') ||
        lowerMessage.contains('new task') ||
        lowerMessage.contains('task to do');
  }
}

class HttpException implements Exception {
  final String message;
  final int statusCode;

  const HttpException(this.message, {required this.statusCode});

  @override
  String toString() => 'HttpException: $message (Status code: $statusCode)';
}
