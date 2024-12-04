import 'package:flutter/material.dart';

class FileUtils {
  static String formatFileSize(int size) {
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }

  static IconData getFileIcon(String fileType) {
    switch (fileType) {
      case 'image':
        return Icons.image;
      case 'document':
        return Icons.description;
      case 'audio':
        return Icons.audiotrack;
      case 'video':
        return Icons.video_file;
      default:
        return Icons.insert_drive_file;
    }
  }
}
