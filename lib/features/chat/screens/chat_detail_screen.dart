import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import '../../../core/services/chat_service.dart';
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
      _loadMessages();
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

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
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

  Future<void> _handleSubmitted(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      _messages.add(ChatMessage(
        content: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      await _chatService.sendMessage(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
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
                  title: Text('重命名会话'),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete, color: Colors.red),
                  title: Text('删除会话', style: TextStyle(color: Colors.red)),
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
            Text('加载失败: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadConversation,
              child: const Text('重试'),
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
        );
      },
    );
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('重命名会话'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '请输入新的会话名称',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isEmpty) return;

                try {
                  await _chatService.renameConversation(
                      widget.conversationId, newName);
                  setState(() {
                    _conversationTitle = newName;
                  });
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('重命名成功')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('重命名失败: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeleteConfirmDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话'),
        content: const Text('确定要删除这个会话吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _chatService.deleteConversation(widget.conversationId);
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会话已删除')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
