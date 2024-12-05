import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

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

  static Future<dynamic> compressImage(XFile image) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath = path.join(
      tempDir.path,
      'compressed_${path.basename(image.path)}',
    );

    // 压缩图片
    final compressedFile = await FlutterImageCompress.compressAndGetFile(
      image.path,
      targetPath,
      quality: 70, // 压缩质量，0-100
      minWidth: 1024, // 最小宽度
      minHeight: 1024, // 最小高度
    );

    return compressedFile;

  }
}
