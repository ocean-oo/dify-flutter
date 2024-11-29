import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';

class MessageBubble extends StatelessWidget {
  final String message;
  final bool isUser;
  final DateTime timestamp;
  final bool isStreaming;
  static final _log = Logger('MessageBubble');

  const MessageBubble({
    super.key,
    required this.message,
    required this.isUser,
    required this.timestamp,
    this.isStreaming = false,
  });

  Widget _buildImage(Uri uri, String? title, String? alt) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: 400,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          uri.toString(),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            _log.warning('图片加载失败: $uri', error, stackTrace);
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.grey[300]!,
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    color: Colors.grey[400],
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    alt ?? '图片加载失败',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (title != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  strokeWidth: 2,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(timestamp);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor,
              child: const Icon(Icons.android, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 10.0,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Theme.of(context).primaryColor
                        : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: isUser
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      MarkdownBody(
                        data: message,
                        imageBuilder: _buildImage,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                            color: isUser
                                ? Colors.white
                                : Theme.of(context).textTheme.bodyLarge?.color,
                            fontSize: 16,
                          ),
                          code: TextStyle(
                            backgroundColor: isUser
                                ? Theme.of(context).primaryColor
                                : Theme.of(context).cardColor,
                            color: isUser
                                ? Colors.white
                                : Theme.of(context).textTheme.bodyLarge?.color,
                            fontSize: 14,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: isUser
                                ? Theme.of(context).primaryColor
                                : Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          blockquote: TextStyle(
                            color: isUser
                                ? Colors.white70
                                : Theme.of(context).textTheme.bodyLarge?.color,
                            fontSize: 16,
                          ),
                          h1: TextStyle(
                            color: isUser
                                ? Colors.white
                                : Theme.of(context).textTheme.bodyLarge?.color,
                            fontSize: 24,
                          ),
                          h2: TextStyle(
                            color: isUser
                                ? Colors.white
                                : Theme.of(context).textTheme.bodyLarge?.color,
                            fontSize: 20,
                          ),
                          h3: TextStyle(
                            color: isUser
                                ? Colors.white
                                : Theme.of(context).textTheme.bodyLarge?.color,
                            fontSize: 18,
                          ),
                          em: TextStyle(
                            color: isUser
                                ? Colors.white
                                : Theme.of(context).textTheme.bodyLarge?.color,
                            fontStyle: FontStyle.italic,
                          ),
                          strong: TextStyle(
                            color: isUser
                                ? Colors.white
                                : Theme.of(context).textTheme.bodyLarge?.color,
                            fontWeight: FontWeight.bold,
                          ),
                          a: TextStyle(
                            color: isUser
                                ? Colors.white
                                : Theme.of(context).primaryColor,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        onTapLink: (text, href, title) async {
                          if (href != null) {
                            try {
                              final url = Uri.parse(href);
                              final canLaunch = await canLaunchUrl(url);
                              if (canLaunch) {
                                await launchUrl(
                                  url,
                                  mode: LaunchMode.externalApplication,
                                );
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('无法打开链接: $href'),
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              _log.severe(
                                '打开链接时出错$e',
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('打开链接失败: $e'),
                                  ),
                                );
                              }
                            }
                          }
                        },
                      ),
                      if (isStreaming) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isUser
                                  ? Colors.white
                                  : Theme.of(context).primaryColor,
                            ),
                          ),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          time,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}
