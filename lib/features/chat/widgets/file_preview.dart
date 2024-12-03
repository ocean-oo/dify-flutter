import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:open_file/open_file.dart';
import '../models/uploaded_file.dart';
import 'package:logging/logging.dart';

class FilePreview extends StatelessWidget {
  final UploadedFile file;
  final bool fullScreen;
  static final _log = Logger('FilePreview');

  const FilePreview({
    super.key,
    required this.file,
    this.fullScreen = false,
  });

  Future<void> _openFile() async {
    if (file.file == null) return;

    try {
      await OpenFile.open(file.file!.path);
    } catch (e) {
      _log.severe('打开文件失败', e);
      rethrow;
    }
  }

  Widget _buildPreviewContent() {
    if (file.file == null) {
      return const Center(
        child: Text('Can not preview this file'),
      );
    }

    switch (file.getFileType()) {
      case 'image':
        return InteractiveViewer(
          child: Image.file(
            file.file!,
            fit: BoxFit.contain,
          ),
        );
      case 'document':
        if (file.extension.toLowerCase() == 'pdf') {
          return Center(
            child: TextButton(
              onPressed: _openFile,
              child: const Text('Open with System PDF Viewer'),
            ),
          );
        }
        return FutureBuilder<String>(
          future: file.file!.readAsString(),
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
        return Center(
          child: TextButton(
            onPressed: _openFile,
            child: const Text('Open with System App'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!fullScreen) {
      return _buildPreviewContent();
    }

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
