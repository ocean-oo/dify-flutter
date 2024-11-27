import 'package:flutter/material.dart';
import '../widgets/chat_list_item.dart';
import '../../../core/services/chat_service.dart';
import '../models/conversation.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({Key? key}) : super(key: key);

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ChatService _chatService = ChatService();
  List<Conversation> _conversations = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    if (_isLoading) return;

    print('=== 开始刷新会话列表 ===');
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final conversations = await _chatService.getConversations();
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _isLoading = false;
      });
      print('=== 会话列表刷新完成，共 ${conversations.length} 个会话 ===');
    } catch (e) {
      print('=== 会话列表刷新失败: $e ===');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    print('当前时间: $now');
    print('会话时间: $timestamp');
    print('时间差: $difference');

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      final minutes = difference.inMinutes;
      print('分钟差: $minutes');
      return '${minutes}分钟前';
    } else if (difference.inDays < 1) {
      final hours = difference.inHours;
      print('小时差: $hours');
      return '${hours}小时前';
    } else if (difference.inDays < 30) {
      final days = difference.inDays;
      print('天数差: $days');
      return '${days}天前';
    } else {
      return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    }
  }

  Future<String?> _showNewChatDialog(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('开始新对话'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '请输入您想问的问题',
            ),
            autofocus: true,
            maxLines: 3,
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
                final message = controller.text.trim();
                if (message.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入问题内容')),
                  );
                  return;
                }
                Navigator.of(context).pop(message);
              },
              child: const Text('发送'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天'),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          try {
            final message = await _showNewChatDialog(context);
            if (message == null || message.isEmpty) return;
            
            _chatService.resetConversation();
            final response = await _chatService.sendMessage(message);
            
            if (response.conversationId != null && mounted) {
              Navigator.pushNamed(
                context,
                '/chat_detail',
                arguments: response.conversationId,
              ).then((_) => _loadConversations());
            }
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('创建新会话失败: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('加载失败: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadConversations,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConversations,
      child: _conversations.isEmpty
          ? ListView(
              children: const [
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('暂无对话，点击右下角按钮开始新对话'),
                  ),
                ),
              ],
            )
          : ListView.builder(
              itemCount: _conversations.length,
              padding: const EdgeInsets.all(8.0),
              itemBuilder: (context, index) {
                final conversation = _conversations[index];
                print('渲染会话: ${conversation.id}');
                print('会话创建时间: ${conversation.createdAt}');
                print('会话更新时间: ${conversation.updatedAt}');
                final formattedTime = _formatTimestamp(conversation.updatedAt);
                print('格式化后时间: $formattedTime');
                return ChatListItem(
                  title: conversation.name ?? '新对话',
                  lastMessage: '点击继续对话',
                  timestamp: formattedTime,
                  onTap: () {
                    Navigator.pushNamed(
                      context,
                      '/chat_detail',
                      arguments: conversation.id,
                    ).then((_) => _loadConversations());
                  },
                );
              },
            ),
    );
  }
}
