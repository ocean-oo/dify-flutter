import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:logging/logging.dart';
import 'package:open_file/open_file.dart';

import '../models/uploaded_file.dart';

class FilePreview extends StatelessWidget {
  final UploadedFile file;
  static final _log = Logger('FilePreview');

  const FilePreview({
    super.key,
    required this.file,
  });

  Future<void> _openFile() async {
    if (file.filePath == null) return;

    try {
      await OpenFile.open(file.filePath);
    } catch (e) {
      _log.severe('打开文件失败', e);
      rethrow;
    }
  }

  Widget _buildPreviewContent() {
    if (file.filePath == null) {
      return const Center(
        child: Text('Can not preview this file'),
      );
    }

    switch (file.getFileType()) {
      case 'image':
        return InteractiveViewer(
          child: Image.file(
            File(file.filePath!),
            fit: BoxFit.contain,
          ),
        );
      case 'document':
        if (file.extension.toLowerCase() == 'pdf') {
          _openFile();
          return const Center(child: Text('Open with system app...'));
        }
        return FutureBuilder<String>(
          future: File(file.filePath!).readAsString(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Can not get file content: ${snapshot.error}'),
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: file.extension.toLowerCase() == 'md'
                  ? MarkdownBody(data: snapshot.data!)
                  : SelectableText(snapshot.data!),
            );
          },
        );
      default:
        _openFile();
        return const Center(
          child: Text('Open with system app...'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(file.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                try {
                  await _openFile();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Open File Failed: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
        body: _buildPreviewContent(),
      ),
    );
  }
}
