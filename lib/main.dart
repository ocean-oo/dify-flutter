import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'core/config/api_config.dart';
import 'features/chat/screens/chat_detail_screen.dart';
import 'features/chat/screens/chat_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint(
        '${record.level.name}: ${record.loggerName}: ${record.time}: ${record.message}');
  });
  await ApiConfig.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return MaterialPageRoute(
            builder: (context) => const ChatListScreen(),
          );
        } else if (settings.name == '/chat_detail') {
          final conversationId = settings.arguments as String?;
          return MaterialPageRoute(
            builder: (context) => ChatDetailScreen(
              conversationId: conversationId,
            ),
          );
        }
        return null;
      },
    );
  }
}
