import 'package:flutter/foundation.dart';

/// 一次可用更新（GitHub Release 元数据）。
/// tag 约定为 "b<构建号>"，构建号即 Android versionCode（CI 的 run number），
/// App 端拿它与本地 versionCode 比较判断是否有新版。
@immutable
class AppRelease {
  const AppRelease({
    required this.buildNumber,
    required this.title,
    required this.notes,
    required this.apkUrl,
    required this.apkSize,
  });

  final int buildNumber;
  final String title;
  final String notes;
  final String apkUrl;
  final int apkSize;

  /// 从 GitHub Releases API 的 release JSON 解析。
  /// tag 不符约定或找不到 APK 资产时抛 [FormatException]。
  factory AppRelease.fromGithub(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String? ?? '').trim();
    final match = RegExp(r'^b(\d+)$').firstMatch(tag);
    if (match == null) {
      throw FormatException('release tag 不是 b<构建号> 格式: $tag');
    }
    Map<String, dynamic>? apk;
    for (final a in (json['assets'] as List? ?? const []).whereType<Map>()) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) {
        apk = Map<String, dynamic>.from(a);
        break;
      }
    }
    if (apk == null) {
      throw const FormatException('release 里没有 APK 文件');
    }
    return AppRelease(
      buildNumber: int.parse(match.group(1)!),
      title: (json['name'] as String? ?? '').trim(),
      notes: (json['body'] as String? ?? '').trim(),
      apkUrl: apk['browser_download_url'] as String? ?? '',
      apkSize: apk['size'] as int? ?? 0,
    );
  }
}
