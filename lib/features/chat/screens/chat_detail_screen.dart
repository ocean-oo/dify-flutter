import 'package:flutter/material.dart';
import '../../../core/services/chat_service.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_bubble.dart';

class ChatDetailScreen extends StatefulWidget {
  final String conversationId;
  
  const ChatDetailScreen({
    Key? key,
    required this.conversationId,
  }) : super(key: key);

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final ChatService _chatService = ChatService();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _error;
  String _conversationTitle = '加载中...';
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadConversation();
  }

  Future<void> _loadConversation() async {
    print('=== 开始加载会话 ===');
    print('会话ID: ${widget.conversationId}');
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _chatService.setConversationId(widget.conversationId);
      // 获取会话列表来获取当前会话的标题
      final conversations = await _chatService.getConversations();
      final currentConversation = conversations.firstWhere(
        (conv) => conv.id == widget.conversationId,
        orElse: () => throw Exception('找不到当前会话'),
      );
      
      setState(() {
        _conversationTitle = currentConversation.name ?? '新对话';
      });
      
      await _loadHistoryMessages();
    } catch (e) {
      print('加载会话出错: $e');
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadHistoryMessages() async {
    print('=== 开始加载历史消息 ===');
    print('当前会话ID: ${_chatService.currentConversationId}');
    
    if (_chatService.currentConversationId == null) {
      print('没有会话ID，跳过加载历史消息');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      print('正在获取历史消息...');
      final messages = await _chatService.getMessageHistory(_chatService.currentConversationId!);
      print('获取到 ${messages.length} 条历史消息');
      
      setState(() {
        _messages.clear();
        _messages.addAll(messages);
      });
      
      print('历史消息加载完成');
      
      // 使用 WidgetsBinding 确保在下一帧渲染完成后滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      print('加载历史消息出错: $e');
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
      _messages.add(
        ChatMessage(
          content: text,
          isUser: true,
          timestamp: DateTime.now(),
        ),
      );
    });
    _scrollToBottom();

    try {
      ChatMessage? streamingMessage;
      
      await for (final response in _chatService.sendMessageStream(text)) {
        setState(() {
          // 如果是新的流式消息，添加到消息列表
          if (streamingMessage == null) {
            streamingMessage = response;
            _messages.add(streamingMessage!);
          } else {
            // 更新现有的流式消息
            final index = _messages.indexOf(streamingMessage!);
            streamingMessage = response;
            _messages[index] = streamingMessage!;
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending message: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _resetConversation() {
    setState(() {
      _messages.clear();
      _chatService.resetConversation();
    });
    // 重置后重新加载会话列表
    _loadConversation();
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
          if (_isLoading)
            const LinearProgressIndicator(),
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
                  await _chatService.renameConversation(widget.conversationId, newName);
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
        Navigator.pop(context); // 返回聊天列表
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
