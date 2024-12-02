import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/services/file_upload_service.dart';
import 'package:logging/logging.dart';

class ChatInput extends StatefulWidget {
  final Future<void> Function(String message, {List<UploadedFile>? files})
      onSend;
  final bool enabled;

  const ChatInput({
    Key? key,
    required this.onSend,
    this.enabled = true,
  }) : super(key: key);

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  static final _log = Logger('ChatInput');
  final TextEditingController _textController = TextEditingController();
  final FileUploadService _fileUploadService = FileUploadService();
  final List<UploadedFile> _uploadedFiles = [];
  bool _isUploading = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);

      if (image != null) {
        await _uploadFile(File(image.path));
      }
    } catch (e) {
      _log.severe('选择图片失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();

      if (result != null) {
        final file = File(result.files.single.path!);
        await _uploadFile(file);
      }
    } catch (e) {
      _log.severe('选择文件失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick file: $e')),
        );
      }
    }
  }

  Future<void> _uploadFile(File file) async {
    setState(() {
      _isUploading = true;
    });

    try {
      final uploadedFile = await _fileUploadService.uploadFile(file);
      setState(() {
        _uploadedFiles.add(uploadedFile);
      });
    } catch (e) {
      _log.severe('上传文件失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload file: $e')),
        );
      }
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  void _handleSubmitted(String text) {
    final message = text.trim();
    if (message.isEmpty) return;

    _log.info('准备发送消息，当前上传的文件数量: ${_uploadedFiles.length}');
    if (_uploadedFiles.isNotEmpty) {
      _log.info('文件列表: ${_uploadedFiles.map((f) => f.name).join(', ')}');
    }

    widget.onSend(
      message,
      files: _uploadedFiles.isNotEmpty ? _uploadedFiles : null,
    );

    _textController.clear();
    setState(() {
      _uploadedFiles.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_uploadedFiles.isNotEmpty)
          Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _uploadedFiles.length,
              itemBuilder: (context, index) {
                final file = _uploadedFiles[index];
                return Card(
                  child: Container(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (file.mimeType.startsWith('image/'))
                          Image.file(
                            File(file.name),
                            height: 40,
                            width: 40,
                            fit: BoxFit.cover,
                          )
                        else
                          const Icon(Icons.insert_drive_file),
                        const SizedBox(width: 8),
                        Text(file.name),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              _uploadedFiles.removeAt(index);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                offset: const Offset(0, -2),
                blurRadius: 4,
                color: Colors.black.withOpacity(0.1),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.image),
                onPressed: widget.enabled && !_isUploading ? _pickImage : null,
              ),
              IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: widget.enabled && !_isUploading ? _pickFile : null,
              ),
              Expanded(
                child: TextField(
                  controller: _textController,
                  enabled: widget.enabled && !_isUploading,
                  decoration: InputDecoration(
                    hintText:
                        _isUploading ? 'Uploading file...' : 'Type a message',
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _handleSubmitted,
                ),
              ),
              IconButton(
                icon: _isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                onPressed: widget.enabled && !_isUploading
                    ? () => _handleSubmitted(_textController.text)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
