import 'package:chat_app/features/chat/screens/chat_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
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
  final _logger = Logger('ChatListScreen');
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

    _logger.info('=== 开始刷新会话列表 ===');
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
      _logger.info('=== 会话列表刷新完成，共 ${conversations.length} 个会话 ===');
    } catch (e) {
      _logger.info('=== 会话列表刷新失败: $e ===');
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

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      final minutes = difference.inMinutes;
      return '$minutes分钟前';
    } else if (difference.inDays < 1) {
      final hours = difference.inHours;
      return '$hours小时前';
    } else if (difference.inDays < 30) {
      final days = difference.inDays;
      return '$days天前';
    } else {
      return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
    }
  }

  void _openChat(Conversation conversation) async {
    final needRefresh = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetailScreen(
          conversationId: conversation.id,
          title: conversation.name,
        ),
      ),
    );

    // 如果返回值为 true，说明需要刷新列表
    if (needRefresh == true) {
      _loadConversations();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天'),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(
            context,
            '/chat_detail',
          ).then((_) => _loadConversations());
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
                _logger.info('渲染会话: ${conversation.id}');
                final formattedTime = _formatTimestamp(conversation.updatedAt);
                return ChatListItem(
                  title: conversation.name,
                  lastMessage: '点击继续对话',
                  timestamp: formattedTime,
                  onTap: () {
                    _openChat(conversation);
                  },
                );
              },
            ),
    );
  }
}
