import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_release.dart';
import 'settings.dart';

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 应用内自更新：查 GitHub Releases（公开仓库免令牌；fork 到私有仓库自用时
/// 可在设置里配只读令牌）→ 下载 APK → 调系统安装器。
/// 联网范围仅限 https 的 GitHub 域名白名单；令牌只存手机本地，与 AI Key 同一存放策略。
class UpdateService {
  UpdateService(this._settings, {http.Client? client})
      : _client = client ?? http.Client();

  final Settings _settings;
  final http.Client _client;

  static const _repo = 'kelinpan0524-cell/baoji-timer';
  static const _timeout = Duration(seconds: 15);
  static const _channel = MethodChannel('baoji/updater');

  /// 带令牌的请求头；公开仓库匿名访问则不带 Authorization。
  Map<String, String> _authHeaders(String accept) {
    final token = _settings.ghUpdateToken.trim();
    return {
      'Accept': accept,
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// 当前安装的构建号（Android versionCode）。
  Future<int> installedBuildNumber() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// 拉最新 Release；已是最新返回 null，有新版返回元数据。
  /// 公开仓库匿名可查；私有仓库需在设置里配令牌（401 时提示重新生成）。
  Future<AppRelease?> checkLatest() async {
    final http.Response resp;
    try {
      resp = await _client
          .get(
            Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
            headers: _authHeaders('application/vnd.github+json'),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const UpdateException('检查更新超时，稍后再试');
    } on SocketException {
      throw const UpdateException('网络不可用');
    } on http.ClientException catch (e) {
      throw UpdateException('网络请求失败：${e.message}');
    }
    switch (resp.statusCode) {
      case 200:
        break;
      case 401:
        throw const UpdateException('令牌无效或已过期，请在 GitHub 重新生成');
      case 404:
        throw const UpdateException('还没有任何发布版本');
      default:
        throw UpdateException('检查更新失败（HTTP ${resp.statusCode}）');
    }
    final Map<String, dynamic> json;
    final AppRelease release;
    try {
      json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      release = AppRelease.fromGithub(json);
    } on FormatException {
      throw const UpdateException('发布版本信息异常（可能 CI 出包失败）');
    } on TypeError {
      throw const UpdateException('发布版本信息异常（可能 CI 出包失败）');
    }
    if (release.buildNumber <= await installedBuildNumber()) return null;
    return release;
  }

  /// 下载 APK 到应用缓存目录，返回文件路径。
  /// 走 Releases asset API（browser_download_url 带 token 恒 404）：
  /// 第一跳 api.github.com（有令牌则带上）302 到签名 CDN，第二跳不能再带令牌。
  Future<String> downloadApk(AppRelease release,
      {void Function(int received, int total)? onProgress}) async {
    final assetApiUrl =
        'https://api.github.com/repos/$_repo/releases/assets/${release.assetId}';
    final first = http.Request('GET', Uri.parse(assetApiUrl))
      ..headers.addAll(_authHeaders('application/octet-stream'))
      ..followRedirects = false;
    final redirected = await _client.send(first).timeout(_timeout);
    var url = assetApiUrl;
    final status = redirected.statusCode;
    if (status == 301 || status == 302) {
      await redirected.stream.drain<void>();
      url = redirected.headers['location'] ?? '';
    } else if (status != 200) {
      throw UpdateException('下载失败（HTTP $status）');
    }
    final urlError = downloadUrlError(url);
    if (urlError != null) throw UpdateException(urlError);

    // CDN 签名地址不需要（也不能）带令牌
    final stream = await _client
        .send(http.Request('GET', Uri.parse(url)))
        .timeout(_timeout);
    if (stream.statusCode != 200) {
      throw UpdateException('下载失败（HTTP ${stream.statusCode}）');
    }
    final total = stream.contentLength ?? release.apkSize;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/baoji_update.apk');
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in stream.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (total > 0 && received < total) {
      try {
        await file.delete();
      } on FileSystemException {
        // 缓存文件，残留无碍
      }
      throw const UpdateException('下载不完整，请重试');
    }
    return file.path;
  }

  /// 是否已获得"安装未知应用"授权（Android 8+）。
  Future<bool> canRequestInstall() async =>
      await _channel.invokeMethod<bool>('canRequestInstall') ?? true;

  Future<void> openInstallPermissionSettings() =>
      _channel.invokeMethod<void>('openInstallPermissionSettings');

  /// 唤起系统安装器安装 [path] 指向的 APK。
  Future<void> installApk(String path) =>
      _channel.invokeMethod<void>('installApk', {'path': path});

  /// 启动时静默检查：有新版只点亮"设置"入口红点，绝不弹窗（训练专注红线）。
  Future<void> silentCheck() async {
    try {
      final release = await checkLatest();
      _settings.set(() => _settings.pendingUpdate = release);
    } on Exception {
      // 静默失败：启动检查不打扰用户，设置页里手动查会给出原因
    }
  }

  /// 下载/跳转地址安全校验（白名单外、非 https 一律拒绝），合法返回 null。
  @visibleForTesting
  static String? downloadUrlError(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.isScheme('https')) {
      return '下载地址不安全（仅允许 https）';
    }
    final host = uri.host;
    final allowed = host == 'api.github.com' ||
        host == 'github.com' ||
        host.endsWith('.github.com') ||
        host.endsWith('.githubusercontent.com');
    if (!allowed) {
      return '下载地址不在 GitHub 域名白名单内';
    }
    return null;
  }
}
