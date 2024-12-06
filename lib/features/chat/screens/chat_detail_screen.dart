import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import '../../../core/services/chat_service.dart';
import '../models/chart_message.dart';
import '../models/uploaded_file.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_bubble.dart';

class ChatDetailScreen extends StatefulWidget {
  final String? conversationId;
  final String? title;

  const ChatDetailScreen({
    Key? key,
    this.conversationId,
    this.title,
  }) : super(key: key);

  static Route<bool> route({Map<String, dynamic>? arguments}) {
    return MaterialPageRoute<bool>(
      builder: (context) => ChatDetailScreen(
        conversationId: arguments?['id'] as String?,
        title: arguments?['title'] as String?,
      ),
    );
  }

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  static final _log = Logger('ChatDetailScreen');
  final ChatService _chatService = ChatService();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _error;
  late String _conversationTitle;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _chatService.setConversationId(widget.conversationId);
    _conversationTitle = widget.title ?? 'New Conversation';
    if (widget.conversationId != null) {
      _loadMessages().then((_) {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
        }
      });
    }
    // 监听流式消息
    _chatService.messageStreamController.stream.listen((message) {
      if (mounted) {
        setState(() {
          // 如果是机器人的消息（非用户消息），总是替换最后一条消息
          if (!message.isUser &&
              _messages.isNotEmpty &&
              !_messages.last.isUser) {
            _messages[_messages.length - 1] = message;
          } else {
            _messages.add(message);
          }
        });
        _scrollToBottom();
      }
    });
  }

  Future<void> _loadConversation() async {
    _log.info('开始加载会话，会话ID: ${widget.conversationId}');

    setState(() {
      _isLoading = true;
      _error = null;
    });
  }

  Future<void> _loadMessages() async {
    _log.info('开始加载历史消息，当前会话ID: ${_chatService.currentConversationId}');

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final messages = await _chatService
          .getMessageHistory(_chatService.currentConversationId!);
      _log.info('获取到 ${messages.length} 条历史消息');

      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(messages);
        });
      }

      _log.info('历史消息加载完成');
    } catch (e) {
      _log.severe('加载历史消息出错', e);
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _handleSubmitted(String text,
      {List<UploadedFile>? files}) async {
    if (text.trim().isEmpty) return;

    _log.info('chat_detail_screen 收到消息，文件数量: ${files?.length ?? 0}');
    if (files != null && files.isNotEmpty) {
      _log.info('文件列表: ${files.map((f) => f.name).join(', ')}');
    }

    ChatMessage? resMessage;
    ChatMessage sendMessage = ChatMessage(
      content: text,
      isUser: true,
      timestamp: DateTime.now(),
      files: files,
    );

    setState(() {
      _messages.add(sendMessage);
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      resMessage = await _chatService.sendMessage(sendMessage);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send message failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
    if (widget.conversationId == null && resMessage!.conversationId != null) {
      _log.info('新会话创建，ID: ${resMessage.conversationId}');
      final name = await _chatService.renameConversation(
        resMessage.conversationId!,
        '',
        autoGenerate: true,
      );
      _log.info('获取到的名称: $name');
      if (mounted) {
        setState(() {
          _conversationTitle = name;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_conversationTitle),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case 'rename':
                  _showRenameDialog(context);
                  break;
                case 'delete':
                  _showDeleteConfirmDialog(context);
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'rename',
                child: ListTile(
                  leading: Icon(Icons.edit),
                  title: Text('Rename'),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete),
                  title: Text('Delete'),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          if (_isLoading) const LinearProgressIndicator(),
          ChatInput(
            onSend: _handleSubmitted,
            enabled: !_isLoading,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_isLoading && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Load failed: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadConversation,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8.0),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return MessageBubble(
          message: message.content,
          isUser: message.isUser,
          timestamp: message.timestamp,
          isStreaming: message.isStreaming,
          files: message.files,
        );
      },
    );
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final controller = TextEditingController(text: _conversationTitle);

    // 在async操作前获取所有需要的context相关对象
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Conversation'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter new name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              Navigator.of(context).pop();

              try {
                await _chatService.renameConversation(
                    widget.conversationId!, newName);
                if (!mounted) return;
                setState(() {
                  _conversationTitle = newName;
                });
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Rename successfully')),
                );
              } catch (e) {
                if (!mounted) return;
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Rename failed: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showDeleteConfirmDialog(BuildContext context) async {
    // 在async操作前获取所有需要的context相关对象
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content:
            const Text('Are you sure you want to delete this conversation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _chatService.deleteConversation(widget.conversationId!);
        if (!mounted) return null;
        navigator.pop(true);
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Conversation deleted')),
        );
      } catch (e) {
        if (!mounted) return null;
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    return confirmed;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
