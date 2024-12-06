import 'package:chat_app/features/chat/screens/chat_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import '../../../core/services/chat_service.dart';
import '../../setting/screens/settings_screen.dart';
import '../models/conversation.dart';
import '../widgets/chat_list_item.dart';

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
      return 'now';
    } else if (difference.inHours < 1) {
      final minutes = difference.inMinutes;
      return '${minutes}m';
    } else if (difference.inDays < 1) {
      final hours = difference.inHours;
      return '${hours}h';
    } else if (difference.inDays < 30) {
      final days = difference.inDays;
      return '${days}d';
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
        title: const Text('CHAT'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
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
            Text('load conversations failed: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadConversations,
              child: const Text('Retry'),
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
                    child: Text('there is no conversation'),
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
