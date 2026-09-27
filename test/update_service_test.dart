import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:baoji_timer/models/app_release.dart';
import 'package:baoji_timer/services/settings.dart';
import 'package:baoji_timer/services/update_service.dart';

void main() {
  group('AppRelease.fromGithub', () {
    Map<String, dynamic> release({
      String tag = 'b42',
      List<Map<String, dynamic>> assets = const [],
    }) =>
        {
          'tag_name': tag,
          'name': 'v1.0.0 (build 42)',
          'body': '### 最近变更\n- abc',
          'assets': assets,
        };

    const apkAsset = {
      'id': 987,
      'name': 'baoji-timer-b42.apk',
      'browser_download_url':
          'https://github.com/kelinpan0524-cell/baoji-timer/releases/download/b42/baoji-timer-b42.apk',
      'size': 27000000,
    };

    test('解析 tag 构建号与 APK 资产', () {
      final rel = AppRelease.fromGithub(release(assets: [
        {'name': 'notes.md', 'browser_download_url': 'https://x/n.md', 'size': 10},
        apkAsset,
      ]));
      expect(rel.buildNumber, 42);
      expect(rel.title, 'v1.0.0 (build 42)');
      expect(rel.notes, contains('最近变更'));
      expect(rel.apkSize, 27000000);
      expect(rel.apkUrl, endsWith('baoji-timer-b42.apk'));
      expect(rel.assetId, 987,
          reason: '下载走 asset API（browser_download_url 私仓带 token 恒 404）');
    });

    test('APK 资产缺 id 抛 FormatException（无法构造下载地址）', () {
      expect(
        () => AppRelease.fromGithub(release(assets: [
          {
            'name': 'a.apk',
            'browser_download_url': 'https://x/a.apk',
            'size': 10,
          },
        ])),
        throwsFormatException,
      );
    });

    test('tag 不是 b<构建号> 抛 FormatException', () {
      expect(
        () => AppRelease.fromGithub(release(tag: 'v1.0.0', assets: [apkAsset])),
        throwsFormatException,
      );
    });

    test('没有 APK 资产抛 FormatException', () {
      expect(
        () => AppRelease.fromGithub(release(assets: [
          {'name': 'notes.md', 'browser_download_url': 'https://x/n.md', 'size': 10},
        ])),
        throwsFormatException,
      );
    });
  });

  group('UpdateService.downloadUrlError 域名白名单', () {
    test('https 的 GitHub 域放行', () {
      expect(
        UpdateService.downloadUrlError(
            'https://api.github.com/repos/x/y/releases/latest'),
        isNull,
      );
      expect(
        UpdateService.downloadUrlError(
            'https://github.com/kelinpan0524-cell/baoji-timer/releases/download/b42/a.apk'),
        isNull,
      );
      expect(
        UpdateService.downloadUrlError(
            'https://release-assets.githubusercontent.com/8323222/baoji.apk?X=1'),
        isNull,
      );
      expect(
        UpdateService.downloadUrlError(
            'https://objects.githubusercontent.com/github-production-release/x.apk'),
        isNull,
      );
    });

    test('非 https 拒绝', () {
      expect(
        UpdateService.downloadUrlError(
            'http://objects.githubusercontent.com/a.apk'),
        isNotNull,
      );
    });

    test('GitHub 域名仿冒拒绝', () {
      expect(
        UpdateService.downloadUrlError('https://evil.com/a.apk'),
        isNotNull,
      );
      expect(
        UpdateService.downloadUrlError('https://github.com.evil.cn/a.apk'),
        isNotNull,
      );
    });

    test('本机/内网地址拒绝', () {
      expect(
        UpdateService.downloadUrlError('https://localhost/a.apk'),
        isNotNull,
      );
      expect(
        UpdateService.downloadUrlError('https://127.0.0.1/a.apk'),
        isNotNull,
      );
      expect(
        UpdateService.downloadUrlError('https://10.0.2.2/a.apk'),
        isNotNull,
      );
    });
  });

  group('downloadApk 重定向循环（2026-09-27「安装包损坏」修复）', () {
    late Directory tmp;
    late Settings settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settings = Settings(prefs);
      tmp = await Directory.systemTemp
          .createTemp('update_dl_${DateTime.now().microsecondsSinceEpoch}');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } on FileSystemException {
        // 拆卸竞态无碍
      }
    });

    const release = AppRelease(
      buildNumber: 99,
      title: 'v1.3.0 (build 99)',
      notes: '',
      apkUrl: 'https://github.com/x/y',
      assetId: 42,
      apkSize: 1000,
    );

    test('改名 301 → API 302 → CDN 200：逐跳跟到位，存的是真 APK 字节', () async {
      final apkBytes = List<int>.generate(1000, (i) => i & 0xFF);
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        final host = req.url.host;
        final hasOctet =
            req.headers['accept'] == 'application/octet-stream';
        if (host == 'api.github.com' && req.url.path.contains('/assets/42') &&
            !req.url.path.contains('/repositories/')) {
          // 第一跳：仓库改名 → 301 到规范化 API 地址
          expect(hasOctet, isTrue, reason: 'API 域跳转必须保留 Accept 头');
          return http.Response('', 301, headers: {
            'location':
                'https://api.github.com/repositories/1382069479/releases/assets/42',
          });
        }
        if (host == 'api.github.com' && req.url.path.contains('/repositories/')) {
          // 第二跳：规范化地址 → 302 到签名 CDN（同样要求 Accept 头，
          // 否则 GitHub 回 JSON 元数据——旧 bug 的「损坏安装包」就是它）
          expect(hasOctet, isTrue, reason: '改名跳转后的 API 请求仍要带 Accept');
          return http.Response('', 302, headers: {
            'location':
                'https://release-assets.githubusercontent.com/1/42/app-release.apk?sig=abc',
          });
        }
        // CDN：裸请求拿文件本体
        expect(host, 'release-assets.githubusercontent.com');
        expect(hasOctet, isFalse, reason: 'CDN 跳转不应带 API 头');
        return http.Response.fromStream(http.StreamedResponse(
          Stream.fromIterable([apkBytes]),
          200,
          contentLength: apkBytes.length,
        ));
      });
      final svc = UpdateService(settings, client: client);
      final path = await svc.downloadApk(release,
          tempDirPathOverride: tmp.path);
      final saved = await File(path).readAsBytes();
      expect(saved.length, 1000);
      expect(saved[0], 0);
      expect(saved[999], 0xE7);
      expect(requests.length, 3, reason: '301 → 302 → 200 共三跳');
    });

    test('JSON 元数据冒充 APK（大小不符）被完整性校验拦下', () async {
      final client = MockClient((req) async {
        // 模拟极端情况：对 API 的请求没拿到文件，回了 1KB JSON 且 200
        final json = utf8.encode('{"url":"x","id":42,"size":1000}');
        return http.Response.fromStream(http.StreamedResponse(
          Stream.fromIterable([json]),
          200,
          contentLength: json.length,
        ));
      });
      final svc = UpdateService(settings, client: client);
      await expectLater(
        svc.downloadApk(release, tempDirPathOverride: tmp.path),
        throwsA(isA<UpdateException>()),
      );
      expect(File('${tmp.path}/baoji_update.apk').existsSync(), isFalse,
          reason: '不完整的文件必须删除，不给安装器留下损坏包');
    });
  });
}
