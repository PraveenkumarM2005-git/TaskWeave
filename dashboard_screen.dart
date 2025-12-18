import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/task_provider.dart';
import '../providers/chat_provider.dart';
import '../models/task.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  String _currentFilter = 'all';
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TaskProvider>(context, listen: false).loadSampleTasks();
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _searchController.dispose();
    _tabController.dispose();
    _messageController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  List<Task> _filterTasks(List<Task> tasks) {
    switch (_currentFilter) {
      case 'completed':
        return tasks.where((task) => task.isCompleted).toList();
      case 'pending':
        return tasks.where((task) => !task.isCompleted).toList();
      default:
        return tasks;
    }
  }

  List<Task> _searchTasks(List<Task> tasks, String query) {
    if (query.isEmpty) return tasks;
    final queryLower = query.toLowerCase();
    return tasks
        .where(
          (task) =>
              task.title.toLowerCase().contains(queryLower) ||
              (task.description?.toLowerCase().contains(queryLower) ?? false),
        )
        .toList();
  }

  Widget _buildTasksTab() {
    final tasks = Provider.of<TaskProvider>(context).tasks;
    final filteredTasks = _filterTasks(tasks);
    final searchedTasks = _searchTasks(filteredTasks, _searchController.text);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search tasks...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        _buildFilterChips(),
        Expanded(
          child:
              searchedTasks.isEmpty
                  ? const Center(child: Text('No tasks found'))
                  : ListView.builder(
                    itemCount: searchedTasks.length,
                    itemBuilder: (context, index) {
                      final task = searchedTasks[index];
                      return _buildTaskTile(task);
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildChatTab() {
    final chatProvider = Provider.of<ChatProvider>(context);
    final scrollController = ScrollController();

    // Auto-scroll to bottom when new messages arrive
    void scrollToBottom() {
      if (scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      }
    }

    // Scroll to bottom when messages change
    scrollToBottom();

    return Column(
      children: [
        if (chatProvider.error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8.0),
            color: Colors.red[100],
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    chatProvider.error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    // Clear the error
                    chatProvider.clearError();
                  },
                ),
              ],
            ),
          ),
        Expanded(
          child:
              chatProvider.messages.isEmpty
                  ? const Center(
                    child: Text(
                      'Send a message to start chatting!',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                  : ListView.builder(
                    key: const PageStorageKey('chat-messages'),
                    controller: scrollController,
                    padding: const EdgeInsets.all(8.0),
                    itemCount: chatProvider.messages.length,
                    itemBuilder: (context, index) {
                      final message = chatProvider.messages[index];
                      return _buildMessageBubble(message);
                    },
                  ),
        ),
        if (chatProvider.isLoading)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(),
          ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[200],
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    enabled: !chatProvider.isLoading,
                  ),
                  onSubmitted: (_) => _sendMessage(),
                  enabled: !chatProvider.isLoading,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: chatProvider.isLoading ? null : _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(Message message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: message.isUser ? Colors.blue[100] : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(message.text, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    _messageController.clear();

    try {
      await chatProvider.sendMessage(text, context);
    } catch (e) {
      print('Error sending message: $e');
    }
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildFilterChip('All', 'all'),
          _buildFilterChip('Pending', 'pending'),
          _buildFilterChip('Completed', 'completed'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: _currentFilter == value,
      onSelected: (selected) {
        setState(() {
          _currentFilter = value;
        });
      },
      backgroundColor: Colors.grey[200],
      selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
      labelStyle: TextStyle(
        color:
            _currentFilter == value
                ? Theme.of(context).primaryColor
                : Colors.black87,
      ),
    );
  }

  Widget _buildTaskTile(Task task) {
    final priority = task.priority ?? 'medium';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Checkbox(
          value: task.isCompleted,
          onChanged: (_) {
            Provider.of<TaskProvider>(
              context,
              listen: false,
            ).toggleTaskStatus(task.id);
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📝 ${task.title}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                decoration:
                    task.isCompleted
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
              ),
            ),
            if (task.description?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(
                '📋 ${task.description}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  decoration:
                      task.isCompleted
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                ),
              ),
            ],
            if (task.dueDate != null) ...[
              const SizedBox(height: 4),
              Text(
                '⏰ ${DateFormat('MMM d, y hh:mm a').format(task.dueDate!)}',
                style: TextStyle(
                  fontSize: 13,
                  color:
                      task.dueDate!.isBefore(DateTime.now()) &&
                              !task.isCompleted
                          ? Colors.red
                          : Colors.grey[600],
                  decoration:
                      task.isCompleted
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                ),
              ),
            ],
            if (task.category?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(
                '🏷️ ${task.category}',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.blue[700],
                  decoration:
                      task.isCompleted
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '⚡ Priority: ${priority[0].toUpperCase()}${priority.substring(1)}',
              style: TextStyle(
                fontSize: 13,
                color: _getPriorityColor(priority),
                fontWeight: FontWeight.w500,
                decoration:
                    task.isCompleted
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () {
            Provider.of<TaskProvider>(
              context,
              listen: false,
            ).deleteTask(task.id);
          },
        ),
      ),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // ignore: unused_element
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 30) {
      return 'on ${DateFormat('MMM d, y').format(date)}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'just now';
    }
  }

  void _showAddTaskDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final categoryController = TextEditingController();
    DateTime? dueDate;
    String priority = 'medium';

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add New Task'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: '📝 Task Title',
                        border: OutlineInputBorder(),
                      ),
                      validator:
                          (value) =>
                              value?.isEmpty ?? true
                                  ? 'Title is required'
                                  : null,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: '📋 Description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today),
                      title: Text(
                        dueDate == null
                            ? '⏰ No due date'
                            : '⏰ Due: ${DateFormat('MMM d, y hh:mm a').format(dueDate!)}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_calendar),
                        onPressed: () async {
                          // Store the context in a local variable before async operations
                          final currentContext = context;

                          final date = await showDatePicker(
                            context: currentContext,
                            initialDate: DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );

                          // Check if widget is still mounted
                          if (!mounted) return;

                          if (date != null) {
                            final time = await showTimePicker(
                              context: currentContext,
                              initialTime: TimeOfDay.now(),
                            );

                            // Check if widget is still mounted before setState
                            if (!mounted) return;

                            if (time != null) {
                              setState(() {
                                dueDate = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  time.hour,
                                  time.minute,
                                );
                              });
                            }
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: categoryController,
                      decoration: const InputDecoration(
                        labelText: '🏷️ Category',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.category),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('⚡ Priority', style: TextStyle(fontSize: 16)),
                    StatefulBuilder(
                      builder:
                          (context, setState) => SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'low',
                                label: Text('Low'),
                                icon: Icon(Icons.low_priority),
                              ),
                              ButtonSegment(
                                value: 'medium',
                                label: Text('Med'),
                                icon: Icon(Icons.flag),
                              ),
                              ButtonSegment(
                                value: 'high',
                                label: Text('High'),
                                icon: Icon(Icons.priority_high),
                              ),
                            ],
                            selected: {priority},
                            onSelectionChanged: (Set<String> newSelection) {
                              setState(() => priority = newSelection.first);
                            },
                          ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    final taskProvider = Provider.of<TaskProvider>(
                      context,
                      listen: false,
                    );
                    taskProvider.addTask(
                      title: titleController.text,
                      description:
                          descriptionController.text.isNotEmpty
                              ? descriptionController.text
                              : null,
                      dueDate: dueDate,
                      priority: priority,
                      category:
                          categoryController.text.isNotEmpty
                              ? categoryController.text
                              : null,
                    );
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add Task'),
              ),
            ],
          ),
    );
  }

  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Error signing out')));
      }
    }
  }

  void _handleTabChange() {
    setState(() {}); // Force rebuild when tab changes
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TaskWeave'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Sign out',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          onTap: (index) {
            setState(() {}); // Force rebuild when tab is tapped
          },
          tabs: const [
            Tab(icon: Icon(Icons.task), text: 'Tasks'),
            Tab(icon: Icon(Icons.chat), text: 'AI Assistant'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildTasksTab(), _buildChatTab()],
      ),
      floatingActionButton:
          _tabController.index == 0
              ? FloatingActionButton(
                onPressed: () => _showAddTaskDialog(context),
                child: const Icon(Icons.add),
              )
              : null,
    );
  }
}
