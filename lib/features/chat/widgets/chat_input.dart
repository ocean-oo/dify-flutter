import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/services/file_upload_service.dart';
import 'package:logging/logging.dart';
import '../models/uploaded_file.dart';
import 'file_preview.dart';

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

  String _formatFileSize(int size) {
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }

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

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      for (final file in result.files) {
        if (file.path != null) {
          await _uploadFile(File(file.path!));
        }
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

  IconData _getFileIcon(String fileType) {
    switch (fileType) {
      case 'image':
        return Icons.image;
      case 'video':
        return Icons.videocam;
      case 'audio':
        return Icons.audiotrack;
      case 'document':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  void _showFilePreview(BuildContext context, UploadedFile file) {
    showDialog(
      context: context,
      builder: (context) => FilePreview(file: file, fullScreen: true),
    );
  }

  Widget _buildFileList() {
    return ListView.builder(
      reverse: true, // 从底部开始显示
      itemCount: _uploadedFiles.length,
      itemBuilder: (context, index) {
        final file =
        _uploadedFiles[_uploadedFiles.length - 1 - index]; // 反转索引
        final fileName = file.name.length > 20
            ? '${file.name.substring(0, 27)}...'
            : file.name;
        final fileSize = _formatFileSize(file.size);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 2),
          child: Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            child: InkWell(
              onTap: () => _showFilePreview(context, file),
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  Container(
                    height: 24,
                    width: 24,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .primaryColor
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      _getFileIcon(file.getFileType()),
                      color: Theme.of(context).primaryColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            fileName,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          fileSize,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 14,
                      color:
                      Theme.of(context).textTheme.bodySmall?.color,
                    ),
                    onPressed: () {
                      setState(() {
                        _uploadedFiles.removeAt(
                            _uploadedFiles.length - 1 - index);
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_uploadedFiles.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 120),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: _buildFileList(),
          ),
        Container(
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
              Container(
                margin: const EdgeInsets.only(right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap:
                          widget.enabled && !_isUploading ? _pickImage : null,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.camera_alt_outlined),
                      ),
                    ),
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap:
                          widget.enabled && !_isUploading ? _pickFiles : null,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.file_upload_outlined),
                      ),
                    ),
                  ],
                ),
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
