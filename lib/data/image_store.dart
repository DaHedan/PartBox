import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 物料图片本地存储：文件落在应用文档目录下 `images/`，数据库只存相对路径。
class ImageStore {
  const ImageStore._();

  static const String dirName = 'images';

  static Future<Directory> _directory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, dirName));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String> absolutePath(String relativePath) async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, relativePath);
  }

  static Future<File?> resolve(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return null;
    final file = File(await absolutePath(relativePath));
    return file.existsSync() ? file : null;
  }

  static Future<String?> saveBytes(Uint8List bytes, String name) async {
    if (bytes.isEmpty) return null;
    final dir = await _directory();
    final file = File(p.join(dir.path, _safeName(name)));
    await file.writeAsBytes(bytes, flush: true);
    return p.join(dirName, p.basename(file.path));
  }

  /// 从网络下载图片并本地化，返回相对路径。
  static Future<String?> saveFromUrl(String url, String name) async {
    try {
      final resp = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
      final ext = _extensionOf(url, resp.headers['content-type']);
      return saveBytes(resp.bodyBytes, '$name$ext');
    } catch (_) {
      return null;
    }
  }

  static Future<void> delete(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return;
    final file = await resolve(relativePath);
    if (file != null) await file.delete();
  }

  static String _extensionOf(String url, String? contentType) {
    final lower = url.toLowerCase();
    for (final ext in ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp']) {
      if (lower.contains(ext)) return ext;
    }
    if (contentType != null) {
      if (contentType.contains('png')) return '.png';
      if (contentType.contains('webp')) return '.webp';
      if (contentType.contains('gif')) return '.gif';
    }
    return '.jpg';
  }

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9_\-\.]'), '_');
}
