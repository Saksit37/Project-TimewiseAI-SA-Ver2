import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// บันทึกข้อมูลทั้งหมดของแอปลงในเครื่อง (SharedPreferences)
/// ใช้ได้ทั้ง Android, iOS และเว็บ — ข้อมูลอยู่เฉพาะในเครื่องนั้น ไม่ได้ส่งขึ้นเซิร์ฟเวอร์
class Storage {
  static const _key = 'timewise_state_v1';
  static SharedPreferences? _prefs;

  static bool get ready => _prefs != null;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Map<String, dynamic>? load() {
    final raw = _prefs?.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null; // ข้อมูลเสีย ให้เริ่มใหม่
    }
  }

  static Future<void> save(Map<String, dynamic> data) async {
    final p = _prefs;
    if (p == null) return; // ยังไม่ได้ init (เช่น ตอนรัน test) — ข้ามการบันทึก
    await p.setString(_key, jsonEncode(data));
  }

  static Future<void> clear() async {
    await _prefs?.remove(_key);
  }
}

// ------------------------------------------------------------ แปลง JSON
String? _iso(DateTime? d) => d?.toIso8601String();
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v as String);

Map<String, dynamic> activityToJson(Activity a) => {
      'id': a.id,
      'name': a.name,
      'type': a.type.index,
      'minutes': a.minutes,
      'deadline': _iso(a.deadline),
      'priority': a.priority.index,
      'goal': a.goal,
      'recurring': a.recurring,
      'status': a.status.index,
      'note': a.note,
      'actualMinutes': a.actualMinutes,
      'feedbackGood': a.feedbackGood,
      'feedbackNote': a.feedbackNote,
      'completedAt': _iso(a.completedAt),
    };

Activity activityFromJson(Map<String, dynamic> j) => Activity(
      id: j['id'] as String,
      name: j['name'] as String,
      type: ActivityType.values[j['type'] as int],
      minutes: j['minutes'] as int,
      deadline: _date(j['deadline']) ?? DateTime.now(),
      priority: Priority.values[j['priority'] as int],
      goal: (j['goal'] as String?) ?? '',
      recurring: (j['recurring'] as bool?) ?? false,
      status: ActivityStatus.values[j['status'] as int],
      note: (j['note'] as String?) ?? '',
      actualMinutes: j['actualMinutes'] as int?,
      feedbackGood: j['feedbackGood'] as bool?,
      feedbackNote: (j['feedbackNote'] as String?) ?? '',
      completedAt: _date(j['completedAt']),
    );

Map<String, dynamic> blockToJson(PlanBlock b) => {
      'activityId': b.activityId,
      'slotStart': b.slotStart,
      'minutes': b.minutes,
      'adjusted': b.adjusted,
      'start': b.start,
    };

PlanBlock blockFromJson(Map<String, dynamic> j) => PlanBlock(
      activityId: j['activityId'] as String,
      slotStart: j['slotStart'] as int,
      minutes: j['minutes'] as int,
      adjusted: (j['adjusted'] as bool?) ?? false,
    )..start = (j['start'] as int?) ?? 0;

Map<String, dynamic> historyToJson(HistoryEntry h) => {
      'time': _iso(h.time),
      'kind': h.kind.index,
      'title': h.title,
      'detail': h.detail,
      'result': h.result,
      'optionCode': h.optionCode,
    };

HistoryEntry historyFromJson(Map<String, dynamic> j) => HistoryEntry(
      time: _date(j['time']) ?? DateTime.now(),
      kind: DecisionKind.values[j['kind'] as int],
      title: j['title'] as String,
      detail: j['detail'] as String,
      result: j['result'] as String,
      optionCode: j['optionCode'] as String?,
    );

Map<String, dynamic> noticeToJson(AppNotice n) => {
      'kind': n.kind.index,
      'title': n.title,
      'body': n.body,
      'time': _iso(n.time),
      'unread': n.unread,
      'route': n.route,
    };

AppNotice noticeFromJson(Map<String, dynamic> j) => AppNotice(
      kind: NoticeKind.values[j['kind'] as int],
      title: j['title'] as String,
      body: j['body'] as String,
      time: _date(j['time']) ?? DateTime.now(),
      unread: (j['unread'] as bool?) ?? false,
      route: j['route'] as String?,
    );

Map<String, dynamic> settingsToJson(SystemSettings s) => {
      'weightDeadline': s.weightDeadline,
      'weightPriority': s.weightPriority,
      'weightGoal': s.weightGoal,
      'weightHistory': s.weightHistory,
      'balancedCap': s.balancedCap,
      'aiTimeoutSeconds': s.aiTimeoutSeconds,
      'fallbackPlan': s.fallbackPlan,
      'reminderMinutes': s.reminderMinutes,
      'passwordMinLength': s.passwordMinLength,
      'dataRetentionDays': s.dataRetentionDays,
      'maintenanceMode': s.maintenanceMode,
    };

SystemSettings settingsFromJson(Map<String, dynamic> j) {
  final d = SystemSettings();
  return SystemSettings(
    weightDeadline: (j['weightDeadline'] as int?) ?? d.weightDeadline,
    weightPriority: (j['weightPriority'] as int?) ?? d.weightPriority,
    weightGoal: (j['weightGoal'] as int?) ?? d.weightGoal,
    weightHistory: (j['weightHistory'] as int?) ?? d.weightHistory,
    balancedCap: (j['balancedCap'] as int?) ?? d.balancedCap,
    aiTimeoutSeconds: (j['aiTimeoutSeconds'] as int?) ?? d.aiTimeoutSeconds,
    fallbackPlan: (j['fallbackPlan'] as bool?) ?? d.fallbackPlan,
    reminderMinutes: (j['reminderMinutes'] as int?) ?? d.reminderMinutes,
    passwordMinLength: (j['passwordMinLength'] as int?) ?? d.passwordMinLength,
    dataRetentionDays: (j['dataRetentionDays'] as int?) ?? d.dataRetentionDays,
    maintenanceMode: (j['maintenanceMode'] as bool?) ?? d.maintenanceMode,
  );
}

Map<String, dynamic> logToJson(SystemLog l) => {
      'time': _iso(l.time),
      'service': l.service,
      'level': l.level,
      'detail': l.detail,
      'status': l.status,
    };

SystemLog logFromJson(Map<String, dynamic> j) => SystemLog(
      time: _date(j['time']) ?? DateTime.now(),
      service: j['service'] as String,
      level: j['level'] as String,
      detail: j['detail'] as String,
      status: (j['status'] as String?) ?? 'ปกติ',
    );

List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];

/// แปลงรายการ JSON เป็นโมเดล โดยข้ามรายการที่เสีย
List<T> decodeList<T>(Object? v, T Function(Map<String, dynamic>) f) {
  final out = <T>[];
  for (final m in _maps(v)) {
    try {
      out.add(f(m));
    } catch (_) {}
  }
  return out;
}
