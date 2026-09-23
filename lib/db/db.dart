import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart';

/// SQLite 本地库：唯一数据源。所有查询经 DatabaseProvider。
class Db {
  Db._() : _override = null;
  static final Db instance = Db._();

  /// 测试缝：注入已打开的内存库（sqflite_common_ffi）。
  @visibleForTesting
  Db.forTesting(this._override);

  final Database? _override;
  Future<Database>? _overrideFuture;

  Future<Database>? _dbFuture;

  Future<Database> get database {
    final o = _override;
    if (o != null) {
      // 与生产路径一致：开启外键（级联删除依赖它）
      return _overrideFuture ??= () async {
        await o.execute('PRAGMA foreign_keys = ON');
        return o;
      }();
    }
    final existing = _dbFuture;
    if (existing != null) return existing;
    final dir = getDatabasesPath();
    final future = dir.then((d) => openDatabase(
          p.join(d, 'baoji_timer.db'),
          version: 2,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, v) => createSchema(db),
          onUpgrade: _onUpgrade,
        ));
    _dbFuture = future;
    return future;
  }

  Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      // v2：session_exercises 增加动作级休息秒数 + 新索引
      await db.execute(
          'ALTER TABLE session_exercises ADD COLUMN rest_sec INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_se_name ON session_exercises(name)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_se_session ON session_exercises(session_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sets_se ON sets(session_exercise_id)');
    }
  }

  /// 建表（onCreate 与单元测试共用）。
  @visibleForTesting
  Future<void> createSchema(Database db) async => _onCreate(db, 1);

  Future<void> _onCreate(Database db, int v) async {
    await db.execute('''
      CREATE TABLE plans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        source TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )''');
    await db.execute('''
      CREATE TABLE plan_days(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id INTEGER NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
        weekday INTEGER NOT NULL,
        title TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT ''
      )''');
    await db.execute('''
      CREATE TABLE plan_exercises(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        day_id INTEGER NOT NULL REFERENCES plan_days(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        order_idx INTEGER NOT NULL DEFAULT 0,
        sets INTEGER NOT NULL DEFAULT 3,
        reps_min INTEGER NOT NULL DEFAULT 5,
        reps_max INTEGER NOT NULL DEFAULT 8,
        rest_sec INTEGER NOT NULL DEFAULT 120,
        kind TEXT NOT NULL DEFAULT 'assistance',
        rule TEXT NOT NULL DEFAULT '{}'
      )''');
    await db.execute('''
      CREATE TABLE exercise_meta(
        name TEXT PRIMARY KEY,
        main_muscle TEXT NOT NULL,
        secondary TEXT NOT NULL DEFAULT '',
        is_compound INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        plan_day_id INTEGER,
        plan_day_title TEXT NOT NULL DEFAULT '',
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        status TEXT NOT NULL DEFAULT 'active',
        notes TEXT NOT NULL DEFAULT ''
      )''');
    await db.execute('''
      CREATE TABLE session_exercises(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        order_idx INTEGER NOT NULL DEFAULT 0,
        kind TEXT NOT NULL DEFAULT 'assistance',
        rest_sec INTEGER NOT NULL DEFAULT 0,
        rule TEXT NOT NULL DEFAULT '{}'
      )''');
    await db.execute('''
      CREATE TABLE sets(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_exercise_id INTEGER NOT NULL
          REFERENCES session_exercises(id) ON DELETE CASCADE,
        weight_kg REAL NOT NULL,
        reps INTEGER NOT NULL,
        rir INTEGER NOT NULL DEFAULT 2,
        kind TEXT NOT NULL DEFAULT 'working',
        done_at INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT ''
      )''');
    await db.execute(
        'CREATE INDEX idx_sets_se ON sets(session_exercise_id)');
    await db.execute(
        'CREATE INDEX idx_se_name ON session_exercises(name)');
    await db.execute(
        'CREATE INDEX idx_se_session ON session_exercises(session_id)');
    await db.execute(
        'CREATE INDEX idx_sessions_date ON sessions(date)');
    await db.execute('''
      CREATE TABLE body_metrics(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        weight_kg REAL,
        waist_cm REAL,
        bodyfat_pct REAL
      )''');
    await db.execute('''
      CREATE TABLE lark_sync(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ref_type TEXT NOT NULL,
        ref_id INTEGER NOT NULL,
        lark_event_id TEXT NOT NULL,
        event_date TEXT NOT NULL,
        synced_at INTEGER NOT NULL,
        summary TEXT NOT NULL DEFAULT '',
        UNIQUE(ref_type, ref_id)
      )''');
    await db.execute('''
      CREATE TABLE sync_queue(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        op TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
  }

  // ---------- plans ----------
  Future<Plan> insertPlan(Plan plan) async {
    final db = await database;
    final id = await db.insert('plans', plan.toMap());
    return Plan.fromMap({...plan.toMap(), 'id': id});
  }

  Future<Plan?> activePlan() async {
    final db = await database;
    final rows =
        await db.query('plans', where: 'is_active=1', limit: 1);
    return rows.isEmpty ? null : Plan.fromMap(rows.first);
  }

  /// 全部计划（启用中的排最前，其余按创建时间倒序）。
  Future<List<Plan>> allPlans() async {
    final db = await database;
    final rows = await db
        .query('plans', orderBy: 'is_active DESC, id DESC');
    return rows.map(Plan.fromMap).toList();
  }

  Future<void> renamePlan(int planId, String name) async {
    final db = await database;
    await db.update('plans', {'name': name},
        where: 'id = ?', whereArgs: [planId]);
  }

  Future<void> setActivePlan(int planId) async {
    final db = await database;
    await db.transaction((tx) async {
      await tx.update('plans', {'is_active': 0});
      await tx.update('plans', {'is_active': 1},
          where: 'id = ?', whereArgs: [planId]);
    });
  }

  Future<void> deletePlan(int planId) async {
    final db = await database;
    await db.delete('plans', where: 'id = ?', whereArgs: [planId]);
  }

  /// 各计划训练日/动作数（切换器展示用），一次 GROUP BY 搞定。
  Future<Map<int, int>> planDayCounts() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT plan_id, COUNT(*) AS n FROM plan_days GROUP BY plan_id');
    return {
      for (final r in rows) (r['plan_id'] as num).toInt(): (r['n'] as num).toInt(),
    };
  }

  Future<Map<int, int>> planExerciseCounts() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT d.plan_id AS plan_id, COUNT(*) AS n
      FROM plan_exercises e
      JOIN plan_days d ON d.id = e.day_id
      GROUP BY d.plan_id
    ''');
    return {
      for (final r in rows) (r['plan_id'] as num).toInt(): (r['n'] as num).toInt(),
    };
  }

  // ---------- plan days / exercises ----------
  Future<int> insertPlanDay(PlanDay day) async =>
      (await database).insert('plan_days', day.toMap());

  /// 更新训练日（标题/星期；切换星期由调用方保证目标日空闲）。
  Future<void> updatePlanDay(PlanDay day) async {
    final db = await database;
    await db.update('plan_days', {'title': day.title, 'weekday': day.weekday},
        where: 'id = ?', whereArgs: [day.id]);
  }

  Future<void> deletePlanDay(int dayId) async {
    final db = await database;
    await db.delete('plan_days', where: 'id = ?', whereArgs: [dayId]);
  }

  /// 交换两个训练日的星期（拖动计划编排用：目标日已有内容则对调）。
  Future<void> swapPlanDayWeekdays(PlanDay a, PlanDay b) async {
    final db = await database;
    await db.transaction((tx) async {
      await tx.update('plan_days', {'weekday': -1},
          where: 'id = ?', whereArgs: [a.id]);
      await tx.update('plan_days', {'weekday': b.weekday},
          where: 'id = ?', whereArgs: [a.id]);
      await tx.update('plan_days', {'weekday': a.weekday},
          where: 'id = ?', whereArgs: [b.id]);
    });
  }

  Future<void> updatePlanExercise(PlanExercise ex) async {
    final db = await database;
    await db.update('plan_exercises', ex.toMap(),
        where: 'id = ?', whereArgs: [ex.id]);
  }

  Future<void> deletePlanExercise(int exerciseId) async {
    final db = await database;
    await db.delete('plan_exercises', where: 'id = ?', whereArgs: [exerciseId]);
  }

  /// 按给定顺序重排某天的动作（order_idx = 下标）。
  Future<void> reorderPlanExercises(int dayId, List<int> idsInOrder) async {
    final db = await database;
    final batch = db.batch();
    for (var i = 0; i < idsInOrder.length; i++) {
      batch.update('plan_exercises', {'order_idx': i},
          where: 'id = ?', whereArgs: [idsInOrder[i]]);
    }
    await batch.commit(noResult: true);
  }

  /// 全部已知动作（含肌群映射），编辑器自动补全/校对用。
  Future<List<ExerciseMeta>> allExerciseMeta() async {
    final db = await database;
    final rows =
        await db.query('exercise_meta', orderBy: 'name');
    return rows.map(ExerciseMeta.fromMap).toList();
  }

  Future<int> insertPlanExercise(PlanExercise ex) async =>
      (await database).insert('plan_exercises', ex.toMap());

  Future<List<PlanDay>> planDays(int planId) async {
    final db = await database;
    final rows = await db.query('plan_days',
        where: 'plan_id = ?',
        whereArgs: [planId],
        orderBy: 'weekday, id');
    return rows.map(PlanDay.fromMap).toList();
  }

  Future<List<PlanExercise>> dayExercises(int dayId) async {
    final db = await database;
    final rows = await db.query('plan_exercises',
        where: 'day_id = ?',
        whereArgs: [dayId],
        orderBy: 'order_idx, id');
    return rows.map(PlanExercise.fromMap).toList();
  }

  Future<Map<int, List<PlanExercise>>> daysExercisesMap(
      List<int> dayIds) async {
    final out = <int, List<PlanExercise>>{};
    for (final id in dayIds) {
      out[id] = await dayExercises(id);
    }
    return out;
  }

  Future<void> clearPlanContent(int planId) async {
    final db = await database;
    await db.rawDelete(
        'DELETE FROM plan_exercises WHERE day_id IN '
        '(SELECT id FROM plan_days WHERE plan_id = ?)',
        [planId]);
    await db.delete('plan_days', where: 'plan_id = ?', whereArgs: [planId]);
  }

  // ---------- exercise meta ----------
  Future<void> upsertExerciseMeta(ExerciseMeta meta) async {
    final db = await database;
    await db.insert('exercise_meta', meta.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<ExerciseMeta?> exerciseMeta(String name) async {
    final db = await database;
    final rows = await db.query('exercise_meta',
        where: 'name = ?', whereArgs: [name], limit: 1);
    return rows.isEmpty ? null : ExerciseMeta.fromMap(rows.first);
  }

  // ---------- sessions ----------
  Future<Session> insertSession(Session s) async {
    final db = await database;
    final id = await db.insert('sessions', s.toMap());
    return Session.fromMap({...s.toMap(), 'id': id});
  }

  Future<void> updateSession(int id, Map<String, Object?> fields) async {
    final db = await database;
    await db.update('sessions', fields, where: 'id = ?', whereArgs: [id]);
  }

  Future<Session?> activeSession() async {
    final db = await database;
    final rows = await db
        .query('sessions', where: "status='active'", orderBy: 'id DESC', limit: 1);
    return rows.isEmpty ? null : Session.fromMap(rows.first);
  }

  Future<Session?> sessionById(int id) async {
    final db = await database;
    final rows =
        await db.query('sessions', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Session.fromMap(rows.first);
  }

  Future<List<Session>> sessionsOnDate(String date) async {
    final db = await database;
    final rows = await db.query('sessions',
        where: 'date = ? AND status != ?',
        whereArgs: [date, 'active'],
        orderBy: 'id');
    return rows.map(Session.fromMap).toList();
  }

  /// 返回 [from, to] 闭区间内已完成训练，按日期升序。
  Future<List<Session>> sessionsBetween(String from, String to) async {
    final db = await database;
    final rows = await db.query('sessions',
        where: 'date >= ? AND date <= ? AND status = ?',
        whereArgs: [from, to, 'done'],
        orderBy: 'date, id');
    return rows.map(Session.fromMap).toList();
  }

  Future<List<Session>> recentSessions({int limit = 60}) async {
    final db = await database;
    final rows = await db.query('sessions',
        where: "status = 'done'", orderBy: 'id DESC', limit: limit);
    return rows.map(Session.fromMap).toList().reversed.toList();
  }

  // ---------- session exercises / sets ----------
  Future<int> insertSessionExercise(SessionExercise se) async =>
      (await database).insert('session_exercises', se.toMap());

  Future<List<SessionExercise>> sessionExercises(int sessionId) async {
    final db = await database;
    final rows = await db.query('session_exercises',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'order_idx, id');
    return rows.map(SessionExercise.fromMap).toList();
  }

  Future<int> insertSet(SetEntry set) async =>
      (await database).insert('sets', set.toMap());

  Future<void> deleteSet(int id) async {
    final db = await database;
    await db.delete('sets', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<SetEntry>> setsOfExercise(int sessionExerciseId) async {
    final db = await database;
    final rows = await db.query('sets',
        where: 'session_exercise_id = ?',
        whereArgs: [sessionExerciseId],
        orderBy: 'id');
    return rows.map(SetEntry.fromMap).toList();
  }

  Future<Map<int, List<SetEntry>>> setsOfSession(int sessionId) async {
    final ses = await sessionExercises(sessionId);
    final out = <int, List<SetEntry>>{};
    for (final se in ses) {
      out[se.id!] = await setsOfExercise(se.id!);
    }
    return out;
  }

  /// 某动作全部历史组（按时间正序），用于对比与渐进判定。
  /// [kindFilter] 不为空时 SQL 侧只取该 kind；最多回 2000 行防无界。
  Future<List<SetEntry>> historySets(String exerciseName,
      {int? beforeSessionExerciseId, String? kindFilter}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT s.* FROM sets s
      JOIN session_exercises se ON se.id = s.session_exercise_id
      JOIN sessions ss ON ss.id = se.session_id
      WHERE se.name = ? AND ss.status = 'done'
        AND (? IS NULL OR s.kind = ?)
      ORDER BY s.done_at ASC
      LIMIT 2000
    ''', [exerciseName, kindFilter, kindFilter]);
    var list = rows.map(SetEntry.fromMap).toList();
    if (beforeSessionExerciseId != null) {
      // 截断到指定 session_exercise 之前（不含当前进行中的组）
      final cur = await db.query('sets',
          columns: ['done_at'],
          where: 'session_exercise_id = ?',
          orderBy: 'done_at',
          whereArgs: [beforeSessionExerciseId]);
      if (cur.isNotEmpty) {
        final cutoff = cur.first['done_at'] as int;
        list = list.where((e) => e.doneAt < cutoff).toList();
      }
    }
    return list;
  }

  /// 该动作历史最高重量（PR 判定用聚合查询，避免全量拉取）。
  Future<double> maxWeightOf(String exerciseName) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT MAX(s.weight_kg) AS best FROM sets s
      JOIN session_exercises se ON se.id = s.session_exercise_id
      JOIN sessions ss ON ss.id = se.session_id
      WHERE se.name = ? AND ss.status = 'done' AND s.kind = 'working'
    ''', [exerciseName]);
    return (rows.first['best'] as num?)?.toDouble() ?? 0;
  }

  /// 上次完成该动作的那次训练里的全部正式组（用于"上次成绩"与渐进推荐）。
  /// 按所属 session 定位，避免用毫秒时间戳相等分组。
  Future<List<SetEntry>> lastWorkingSets(String exerciseName) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT s.* FROM sets s
      JOIN session_exercises se ON se.id = s.session_exercise_id
      JOIN sessions ss ON ss.id = se.session_id
      WHERE se.name = ? AND ss.status = 'done'
        AND s.kind = 'working'
        AND se.session_id = (
          SELECT se2.session_id
          FROM session_exercises se2
          JOIN sessions ss2 ON ss2.id = se2.session_id
          WHERE se2.name = ? AND ss2.status = 'done'
          ORDER BY ss2.id DESC
          LIMIT 1
        )
      ORDER BY s.id ASC
    ''', [exerciseName, exerciseName]);
    return rows.map(SetEntry.fromMap).toList();
  }

  // ---------- body metrics ----------
  /// 只更新本次填写的字段，未填字段保留旧值（防止部分录入清空已有数据）。
  Future<void> upsertBodyMetric(BodyMetric bm) async {
    final db = await database;
    final update = <String, Object?>{
      if (bm.weightKg != null) 'weight_kg': bm.weightKg,
      if (bm.waistCm != null) 'waist_cm': bm.waistCm,
      if (bm.bodyFatPct != null) 'bodyfat_pct': bm.bodyFatPct,
    };
    final updated = await db.update('body_metrics', update,
        where: 'date = ?', whereArgs: [bm.date]);
    if (updated == 0) {
      await db.insert('body_metrics', bm.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<BodyMetric>> bodyMetrics({int limit = 180}) async {
    final db = await database;
    final rows = await db
        .query('body_metrics', orderBy: 'date DESC', limit: limit);
    return rows.map(BodyMetric.fromMap).toList().reversed.toList();
  }

  // ---------- lark sync ----------
  Future<void> upsertLarkSync(LarkSync sync) async {
    final db = await database;
    await db.insert('lark_sync', sync.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeLarkSync(String refType, int refId) async {
    final db = await database;
    await db.delete('lark_sync',
        where: 'ref_type = ? AND ref_id = ?', whereArgs: [refType, refId]);
  }

  Future<LarkSync?> larkSyncFor(String refType, int refId) async {
    final db = await database;
    final rows = await db.query('lark_sync',
        where: 'ref_type = ? AND ref_id = ?',
        whereArgs: [refType, refId],
        limit: 1);
    return rows.isEmpty ? null : LarkSync.fromMap(rows.first);
  }

  // ---------- sync queue（离线补写） ----------
  Future<void> enqueueSync(String op, String payload) async {
    final db = await database;
    await db.insert(
        'sync_queue', {'op': op, 'payload': payload, 'created_at': DateTime.now().millisecondsSinceEpoch});
  }

  Future<List<Map<String, dynamic>>> pendingSync() async {
    final db = await database;
    return db.query('sync_queue', orderBy: 'id');
  }

  Future<void> removeSync(int id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- 聚合查询（数据页用，避免 N+1） ----------

  /// 单次 JOIN 拉出时间段内全部训练明细行。
  /// 删除单次训练（级联删除其动作与组记录）。
  Future<void> deleteSession(int sessionId) async {
    final db = await database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  /// 某计划全部训练日的飞书同步记录（清理残留日程用）。
  Future<List<LarkSync>> larkSyncRefsForPlan(int planId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT l.* FROM lark_sync l
      JOIN plan_days d ON d.id = l.ref_id
      WHERE l.ref_type = 'plan_day' AND d.plan_id = ?
    ''', [planId]);
    return rows.map(LarkSync.fromMap).toList();
  }

  Future<List<Map<String, Object?>>> sessionRowsBetween(
      String from, String to) async {
    final db = await database;
    return db.rawQuery('''
      SELECT ss.id AS session_id, ss.date, ss.plan_day_title,
             ss.started_at, ss.ended_at,
             se.id AS se_id, se.name, se.order_idx,
             s.weight_kg, s.reps, s.rir, s.kind
      FROM sessions ss
      JOIN session_exercises se ON se.session_id = ss.id
      LEFT JOIN sets s ON s.session_exercise_id = se.id
      WHERE ss.status = 'done' AND ss.date >= ? AND ss.date <= ?
      ORDER BY ss.id, se.order_idx, s.id
    ''', [from, to]);
  }

  // ---------- export ----------
  Future<Map<String, dynamic>> exportAllJson() async {
    final db = await database;
    return {
      'plans': await db.query('plans'),
      'plan_days': await db.query('plan_days'),
      'plan_exercises': await db.query('plan_exercises'),
      'sessions': await db.query('sessions'),
      'session_exercises': await db.query('session_exercises'),
      'sets': await db.query('sets'),
      'body_metrics': await db.query('body_metrics'),
    };
  }

  Future<void> wipeAll() async {
    final db = await database;
    await db.transaction((tx) async {
      for (final t in [
        'sets',
        'session_exercises',
        'sessions',
        'plan_exercises',
        'plan_days',
        'plans',
        'body_metrics',
        'lark_sync',
        'sync_queue',
      ]) {
        await tx.delete(t);
      }
    });
  }
}
