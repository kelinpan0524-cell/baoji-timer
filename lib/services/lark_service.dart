import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../db/db.dart';
import '../models/models.dart';
import 'settings.dart';

/// 计划日同步规格：LarkService 不反向依赖 PlanRepository。
class PlanDaySyncSpec {
  final int planDayId;
  final int weekday; // 1=周一
  final String title;
  final String detail;
  const PlanDaySyncSpec({
    required this.planDayId,
    required this.weekday,
    required this.title,
    required this.detail,
  });
}

/// 飞书开放平台手机直连客户端（自建应用，日历最小权限）。
///
/// 凭证获取（开发期一次性，用 lark-cli 完成）：
///   1. 飞书开放平台建自建应用，开通日历权限（读写自己主日历）
///   2. lark-cli 走授权拿 refresh_token（有效期 30 天，App 内自动轮换续期）
///   3. 把 App ID / App Secret / refresh_token 填进 App 设置页
/// 运行期 App 用 refresh_token 换 user_access_token（2h），到期自动刷新。
class LarkService {
  LarkService(this._settings, this._db);

  final Settings _settings;
  final Db _db;

  static const _base = 'https://open.feishu.cn';
  static const _doneMarker = '—— 训练完成 ——';

  Future<String?>? _tokenInFlight;

  bool get configured =>
      _settings.larkEnabled &&
      _settings.larkAppId.isNotEmpty &&
      _settings.larkAppSecret.isNotEmpty &&
      _settings.larkRefreshToken.isNotEmpty;

  /// 拿有效 user_access_token；失败返回 null。
  /// single-flight：并发调用共享同一次刷新，避免 refresh_token 轮换竞态。
  Future<String?> ensureToken() {
    if (!configured) return Future.value(null);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_settings.larkAccessToken.isNotEmpty &&
        _settings.larkTokenExpiry - now > 120000) {
      return Future.value(_settings.larkAccessToken);
    }
    final inFlight = _tokenInFlight;
    if (inFlight != null) return inFlight;
    final f = _refreshToken().whenComplete(() => _tokenInFlight = null);
    _tokenInFlight = f;
    return f;
  }

  Future<String?> _refreshToken() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final resp = await http
          .post(
            Uri.parse('$_base/open-apis/authen/v2/oauth/token'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'grant_type': 'refresh_token',
              'client_id': _settings.larkAppId,
              'client_secret': _settings.larkAppSecret,
              'refresh_token': _settings.larkRefreshToken,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      if (resp.statusCode != 200 ||
          data['code'] != 0 ||
          data['access_token'] == null) {
        return null; // refresh_token 过期/失效或网络错误
      }
      _settings.larkAccessToken = data['access_token'] as String;
      _settings.larkTokenExpiry =
          now + ((data['expires_in'] as num?)?.toInt() ?? 6900) * 1000;
      final newRefresh = data['refresh_token'] as String?;
      if (newRefresh != null && newRefresh.isNotEmpty) {
        _settings.larkRefreshToken = newRefresh; // 轮换
      }
      await _settings.save();
      return _settings.larkAccessToken;
    } catch (_) {
      return null;
    }
  }

  /// 拿用户主日历 id（设置页"测试连接"用）。
  Future<String> fetchPrimaryCalendar() async {
    final token = await ensureToken();
    if (token == null) throw const LarkException('授权失效或网络不可用，请检查后重试');
    final resp = await http
        .get(
          Uri.parse('$_base/open-apis/calendar/v4/calendars?page_size=50'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
    final data =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    if (data['code'] != 0) throw LarkException('获取日历失败：${data['msg']}');
    final items = (data['data']?['calendar_list'] as List?) ?? [];
    for (final c in items) {
      final m = Map<String, dynamic>.from(c as Map);
      if (m['type'] == 'primary') return m['calendar_id'] as String;
    }
    if (items.isNotEmpty) {
      return Map<String, dynamic>.from(items.first as Map)['calendar_id']
          as String;
    }
    throw const LarkException('没有可用日历');
  }

  /// 计划日 → 日历事件（有则更新、无则建）。
  /// 失败时入离线队列，联网后由 retryPending 补写。
  Future<void> upsertDayEvent({
    required String date,
    required String title,
    required String detail,
    int? planDayId,
  }) async {
    if (!configured) return;
    try {
      await _upsertDayEventRaw(
          date: date, title: title, detail: detail, planDayId: planDayId);
    } catch (_) {
      await _db.enqueueSync('upsert_day', jsonEncode({
        'date': date,
        'title': title,
        'detail': detail,
        'plan_day_id': planDayId,
      }));
    }
  }

  Future<void> _upsertDayEventRaw({
    required String date,
    required String title,
    required String detail,
    int? planDayId,
  }) async {
    final token = await ensureToken();
    if (token == null) throw const LarkException('no token');
    final cid = _settings.larkCalendarId.isNotEmpty
        ? _settings.larkCalendarId
        : await fetchPrimaryCalendar();
    final startTs =
        _tsOf(date, _settings.larkEventHour, _settings.larkEventMinutes);
    final endTs = startTs + 3600; // 1 小时
    final body = jsonEncode({
      'summary': title,
      'description': detail,
      'start_time': {'timestamp': '$startTs'},
      'end_time': {'timestamp': '$endTs'},
      'reminders': [
        {'minutes': _settings.larkReminderMin}
      ],
    });
    final exist =
        planDayId == null ? null : await _db.larkSyncFor('plan_day', planDayId);
    http.Response resp;
    if (exist != null) {
      resp = await http
          .patch(
            Uri.parse(
                '$_base/open-apis/calendar/v4/calendars/$cid/events/${exist.larkEventId}'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: body,
          )
          .timeout(const Duration(seconds: 20));
    } else {
      resp = await http
          .post(
            Uri.parse('$_base/open-apis/calendar/v4/calendars/$cid/events'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json'
            },
            body: body,
          )
          .timeout(const Duration(seconds: 20));
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    if (data['code'] != 0) throw LarkException('${data['msg']}');
    final eventId =
        (data['data']?['event']?['event_id'] as String?) ?? exist?.larkEventId ?? '';
    if (eventId.isNotEmpty && planDayId != null) {
      await _db.upsertLarkSync(LarkSync(
        refType: 'plan_day',
        refId: planDayId,
        larkEventId: eventId,
        eventDate: date,
        syncedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    }
  }

  /// 训练完成 → 回填摘要到当天事件描述（失败入队）。
  Future<void> backfillSessionSummary({
    required String date,
    required String summary,
  }) async {
    if (!configured) return;
    try {
      await _backfillSessionSummaryRaw(date: date, summary: summary);
    } catch (_) {
      await _db.enqueueSync('session_summary', jsonEncode({
        'date': date,
        'summary': summary,
      }));
    }
  }

  Future<void> _backfillSessionSummaryRaw({
    required String date,
    required String summary,
  }) async {
    final token = await ensureToken();
    if (token == null) throw const LarkException('no token');
    final cid = _settings.larkCalendarId.isNotEmpty
        ? _settings.larkCalendarId
        : await fetchPrimaryCalendar();
    // 找当天含"（训练）"的事件（由本 App 创建，避免误伤用户手建事件）
    final fromTs = _tsOf(date, 0, 0) - 86400;
    final toTs = _tsOf(date, 23, 59) + 86400;
    final resp = await http.get(
      Uri.parse(
          '$_base/open-apis/calendar/v4/calendars/$cid/events?start_time=$fromTs&end_time=$toTs&page_size=50'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 20));
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    if (data['code'] != 0) throw LarkException('${data['msg']}');
    final items = (data['data']?['items'] as List?) ?? [];
    String? eventId;
    String prevDesc = '';
    for (final it in items) {
      final m = Map<String, dynamic>.from(it as Map);
      if ((m['summary'] as String?)?.contains('（训练）') == true) {
        eventId = m['event_id'] as String?;
        prevDesc = (m['description'] as String?) ?? '';
        break;
      }
    }
    if (eventId == null) return;
    // 已回填过就跳过，避免重试时摘要重复追加
    if (prevDesc.contains(_doneMarker)) return;
    final newDesc = prevDesc.isEmpty
        ? '$_doneMarker\n$summary'
        : '$prevDesc\n\n$_doneMarker\n$summary';
    await http.patch(
      Uri.parse('$_base/open-apis/calendar/v4/calendars/$cid/events/$eventId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'description': newDesc}),
    ).timeout(const Duration(seconds: 20));
  }

  /// 删除某计划日对应的日历事件（切计划/删日时清未来日程）。
  /// 尽力而为：失败静默忽略，本地同步记录仍然清除。
  Future<void> removePlanDayEvent(int planDayId) async {
    final sync = await _db.larkSyncFor('plan_day', planDayId);
    if (sync == null) return;
    try {
      final token = await ensureToken();
      if (token == null) return;
      final cid = _settings.larkCalendarId.isNotEmpty
          ? _settings.larkCalendarId
          : await fetchPrimaryCalendar();
      await http
          .delete(
            Uri.parse(
                '$_base/open-apis/calendar/v4/calendars/$cid/events/${sync.larkEventId}'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // 日历侧可能已手动删除/网络不可用：忽略
    }
    await _db.removeLarkSync('plan_day', planDayId);
  }

  /// 把激活计划的训练日写入未来 14 天的飞书日历（计划安装/导入后调用）。
  Future<int> syncUpcomingDays({required List<PlanDaySyncSpec> days}) async {
    if (!configured) return 0;
    final today = DateTime.now();
    var n = 0;
    for (final day in days) {
      for (var i = 0; i < 14; i++) {
        final d = today.add(Duration(days: i));
        if (d.weekday != day.weekday) continue;
        // 不 break：未来 14 天内同一星期会命中 2 次，两周都要安排
        await upsertDayEvent(
          date: fmtYmd(d),
          title: '${day.title}（训练）',
          detail: day.detail,
          planDayId: day.planDayId,
        );
        n++;
      }
    }
    return n;
  }

  /// 启动/联网时补写离线队列。
  /// 重试走 Raw 路径（失败不重新入队），失败项留在原队列行下次再试。
  Future<int> retryPending() async {
    if (!configured) return 0;
    final pending = await _db.pendingSync();
    var done = 0;
    for (final row in pending) {
      final op = row['op'] as String;
      final payload =
          jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      try {
        if (op == 'upsert_day') {
          await _upsertDayEventRaw(
            date: payload['date'] as String,
            title: payload['title'] as String,
            detail: payload['detail'] as String? ?? '',
            planDayId: payload['plan_day_id'] as int?,
          );
        } else if (op == 'session_summary') {
          await _backfillSessionSummaryRaw(
            date: payload['date'] as String,
            summary: payload['summary'] as String? ?? '',
          );
        }
        await _db.removeSync(row['id'] as int);
        done++;
      } catch (_) {
        // 仍失败，留在队列下次再试
      }
    }
    return done;
  }

  static String fmtYmd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int _tsOf(String date, int hour, int minute) {
    final p = date.split('-').map(int.parse).toList();
    final dt = DateTime(p[0], p[1], p[2], hour, minute);
    return dt.millisecondsSinceEpoch ~/ 1000;
  }
}

class LarkException implements Exception {
  final String message;
  const LarkException(this.message);
  @override
  String toString() => message;
}
