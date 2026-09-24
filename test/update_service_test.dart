import 'package:flutter_test/flutter_test.dart';

import 'package:baoji_timer/models/app_release.dart';
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
}
