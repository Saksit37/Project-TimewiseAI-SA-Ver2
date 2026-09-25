import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/decision_engine.dart';
import '../services/storage.dart';
import '../utils/format.dart';

/// สถานะกลางของแอป — บันทึกลงเครื่องอัตโนมัติทุกครั้งที่ข้อมูลเปลี่ยน (ดู services/storage.dart)
/// ในระบบจริงเต็มรูปแบบ ส่วนนี้จะเรียก Backend (Python/FastAPI + PostgreSQL) ตามที่ออกแบบไว้ในรายงาน
final AppState appState = AppState();

class AppState extends ChangeNotifier {
  AppState() {
    _seed();
  }

  /// เวลาปัจจุบัน (อ่านใหม่ทุกครั้ง เพื่อให้เปิดแอปค้างข้ามวันได้ถูกต้อง)
  DateTime get now => DateTime.now();
  DateTime get today => dateOnly(now);
  DateTime at(int dayOffset, int hour, int minute) => DateTime(now.year, now.month, now.day + dayOffset, hour, minute);

  /// แท็บที่เปิดอยู่ในหน้าหลัก (0 หน้าหลัก, 1 กิจกรรม, 2 ตาราง, 3 รายงาน)
  final ValueNotifier<int> homeTab = ValueNotifier<int>(0);

  // ---------------------------------------------------------------- ผู้ใช้
  String userName = 'มิว';
  String email = 'mew.student@example.com';
  DateTime joined = DateTime.now().subtract(const Duration(days: 20));

  /// true = ยังใช้ข้อมูลตัวอย่างสำหรับสาธิต, false = ข้อมูลจริงของผู้ใช้
  bool demoMode = true;

  /// จำการเข้าสู่ระบบไว้ เปิดแอปครั้งต่อไปเข้าหน้าหลักได้ทันที
  bool rememberLogin = false;
  DateTime? planDate;

  // ------------------------------------------------------ ข้อมูลการวางแผน
  final List<Activity> activities = [];
  final List<TimeSlot> slots = [const TimeSlot(13 * 60, 15 * 60), const TimeSlot(18 * 60, 21 * 60)];
  final List<String> allGoals = ['เตรียมสอบ', 'ส่งงานตรงเวลา', 'ดูแลสุขภาพ', 'พัฒนาตนเอง', 'พักผ่อนให้พอ'];
  final List<String> goals = ['เตรียมสอบ', 'ส่งงานตรงเวลา'];
  final Set<int> activeDays = {1, 2, 3, 4, 5};
  final Set<String> excludedFromAi = {};
  String aiNote = 'ช่วงเย็นมักเหนื่อย อยากทำงานที่ใช้สมาธิสูงช่วงบ่าย';

  AiResult? lastResult;
  List<PlanBlock> plan = [];
  String? planCode;
  bool planAdjusted = false;
  DateTime? planConfirmedAt;

  final List<HistoryEntry> history = [];
  final List<AppNotice> notices = [];
  final Map<String, int> postponeCounts = {};

  bool notifyBefore = true;
  bool notifyChange = true;
  bool notifyLog = false;
  bool aiLearn = true;

  // ------------------------------------------------------------ ผู้ดูแลระบบ
  final List<AppUser> users = [];
  SystemSettings settings = SystemSettings();
  final List<SystemLog> logs = [];
  bool aiHealthy = false;
  final List<double> aiLatency = [1.8, 1.9, 2.1, 2.0, 2.4, 3.1, 4.6, 4.2, 3.0, 2.2, 2.0, 1.9];
  int aiRequestsToday = 612;
  final List<int> aiRequestsWeek = [488, 530, 502, 575, 598, 541]; // 6 วันก่อนหน้า (วันนี้ใช้ aiRequestsToday)
  DateTime statusRefreshedAt = DateTime.now();

  int _seq = 0;
  String newId() => 'a${DateTime.now().microsecondsSinceEpoch}${_seq++}';

  // ---------------------------------------------------------------- getters
  int get freeMinutes => slots.fold(0, (s, t) => s + t.minutes);
  List<Activity> get pending => activities.where((a) => a.status != ActivityStatus.done).toList();
  List<Activity> get aiCandidates => pending.where((a) => !excludedFromAi.contains(a.id)).toList();
  int get requiredMinutes => pending.fold(0, (s, a) => s + a.minutes);
  int get unreadCount => notices.where((n) => n.unread).length;

  Activity? byId(String id) {
    for (final a in activities) {
      if (a.id == id) return a;
    }
    return null;
  }

  int plannedMinutesFor(String id) {
    final m = plan.where((b) => b.activityId == id).fold<int>(0, (s, b) => s + b.minutes);
    if (m > 0) return m;
    return byId(id)?.minutes ?? 0;
  }

  DecisionEngine engine() => DecisionEngine(
        activities: aiCandidates,
        slots: slots,
        goals: goals,
        now: now,
        history: activities.where((a) => a.status == ActivityStatus.done).toList(),
        weights: settings.weights,
        balancedCap: settings.balancedCap,
      );

  // ------------------------------------------------------ กิจกรรม (FR-02–04)
  void saveActivity(Activity a) {
    final i = activities.indexWhere((x) => x.id == a.id);
    if (i >= 0) {
      activities[i] = a;
    } else {
      activities.insert(0, a);
    }
    notifyListeners();
  }

  void deleteActivity(String id) {
    activities.removeWhere((a) => a.id == id);
    plan.removeWhere((b) => b.activityId == id);
    notifyListeners();
  }

  // --------------------------------------------- เวลาว่างและเป้าหมาย (FR-05–06)
  void toggleGoal(String g) {
    if (goals.contains(g)) {
      goals.remove(g);
    } else {
      goals.add(g);
    }
    notifyListeners();
  }

  void addGoal(String g) {
    final t = g.trim();
    if (t.isEmpty) return;
    if (!allGoals.contains(t)) allGoals.add(t);
    if (!goals.contains(t)) goals.add(t);
    notifyListeners();
  }

  void toggleDay(int weekday) {
    if (activeDays.contains(weekday)) {
      activeDays.remove(weekday);
    } else {
      activeDays.add(weekday);
    }
    notifyListeners();
  }

  /// คืนค่าข้อความผิดพลาด หรือ null ถ้าเพิ่มสำเร็จ
  String? addSlot(int start, int end) {
    if (end <= start) return 'เวลาสิ้นสุดต้องมากกว่าเวลาเริ่ม';
    if (end - start < 15) return 'ช่วงเวลาต้องยาวอย่างน้อย 15 นาที';
    for (final s in slots) {
      if (start < s.end && end > s.start) return 'ช่วงเวลาซ้อนกับ ${hm(s.start)}–${hm(s.end)}';
    }
    slots.add(TimeSlot(start, end));
    slots.sort((a, b) => a.start.compareTo(b.start));
    notifyListeners();
    return null;
  }

  void removeSlot(int index) {
    final removed = slots.removeAt(index);
    plan.removeWhere((b) => b.slotStart == removed.start);
    notifyListeners();
  }

  void setIncluded(String id, bool included) {
    if (included) {
      excludedFromAi.remove(id);
    } else {
      excludedFromAi.add(id);
    }
    notifyListeners();
  }

  // ------------------------------------------------ วิเคราะห์และเลือกแผน
  AiResult runAnalysis() {
    lastResult = engine().analyse();
    aiRequestsToday++;
    notifyListeners();
    return lastResult!;
  }

  /// FR-12 เลือก/ยอมรับ/ปรับแผน และ FR-13 สร้างตารางเวลา
  void confirmPlan(String code, List<PlanBlock> blocks, {bool adjusted = false}) {
    final eng = engine();
    final laid = eng.layout(blocks.map((b) => b.copy()).toList());
    final title = lastResult?.byCode(code).title ?? '';
    final option = eng.evaluate(code, title, laid);
    plan = laid;
    planDate = today;
    planCode = code;
    planAdjusted = adjusted;
    planConfirmedAt = DateTime.now();
    for (final id in option.postponedIds) {
      final a = byId(id);
      if (a != null) postponeCounts[a.name] = (postponeCounts[a.name] ?? 0) + 1;
    }
    for (final b in laid) {
      final a = byId(b.activityId);
      if (a != null && a.status == ActivityStatus.todo) a.status = ActivityStatus.inProgress;
    }
    history.insert(
      0,
      HistoryEntry(
        time: DateTime.now(),
        kind: adjusted ? DecisionKind.adjusted : DecisionKind.accepted,
        title: 'ทางเลือก $code · $title${adjusted ? ' (ปรับเอง)' : ''}',
        detail: 'จัด ${laid.length} ช่วงเวลา · ทำเสร็จ ${option.completedIds.length} งาน · เลื่อน ${option.postponedIds.length} งาน',
        result: 'กำลังดำเนินการ',
        optionCode: code,
      ),
    );
    if (notifyChange) {
      notices.insert(
        0,
        AppNotice(
          kind: NoticeKind.planChanged,
          title: adjusted ? 'แผนมีการเปลี่ยนแปลง' : 'ยืนยันแผนแล้ว',
          body: laid.map((b) => '“${byId(b.activityId)?.name ?? ''}” ${hm(b.start)}–${hm(b.end)}').join(', '),
          time: DateTime.now(),
          route: 'tab:2',
        ),
      );
    }
    notifyListeners();
  }

  void rejectOptions(String reason) {
    history.insert(
      0,
      HistoryEntry(
        time: DateTime.now(),
        kind: DecisionKind.rejected,
        title: 'ปฏิเสธคำแนะนำ',
        detail: reason.trim().isEmpty ? 'ไม่ได้ระบุเหตุผล' : 'เหตุผล: ${reason.trim()}',
        result: '—',
      ),
    );
    notifyListeners();
  }

  // ------------------------------------------------ ติดตามผล (FR-14, FR-15)
  void recordResult(String id, {required ActivityStatus status, required int actualMinutes, bool? good, String note = ''}) {
    final a = byId(id);
    if (a == null) return;
    a.status = status;
    a.actualMinutes = actualMinutes;
    a.feedbackGood = good;
    a.feedbackNote = note;
    a.completedAt = status == ActivityStatus.done ? DateTime.now() : null;
    notifyListeners();
  }

  // ------------------------------------------------------------ แจ้งเตือน
  void markAllRead() {
    for (final n in notices) {
      n.unread = false;
    }
    notifyListeners();
  }

  void markRead(AppNotice n) {
    n.unread = false;
    notifyListeners();
  }

  void setNotifyBefore(bool v) {
    notifyBefore = v;
    notifyListeners();
  }

  void setNotifyChange(bool v) {
    notifyChange = v;
    notifyListeners();
  }

  void setNotifyLog(bool v) {
    notifyLog = v;
    notifyListeners();
  }

  void setAiLearn(bool v) {
    aiLearn = v;
    notifyListeners();
  }

  // ------------------------------------------------------------ บัญชี (FR-01)
  void updateProfile(String name, String mail) {
    userName = name.trim().isEmpty ? userName : name.trim();
    email = mail.trim().isEmpty ? email : mail.trim();
    notifyListeners();
  }

  // ------------------------------------------------------------ ผู้ดูแลระบบ
  void toggleUserSuspended(AppUser u) {
    u.status = u.status == 'ระงับ' ? 'ใช้งาน' : 'ระงับ';
    notifyListeners();
  }

  void addUser(String name, String mail) {
    users.insert(0, AppUser(name: name, email: mail, joined: DateTime.now(), lastActive: 'ยังไม่เคยเข้าใช้', status: 'รอยืนยันอีเมล'));
    notifyListeners();
  }

  void renameUser(AppUser u, String name) {
    if (name.trim().isEmpty) return;
    u.name = name.trim();
    notifyListeners();
  }

  void saveSettings(SystemSettings next) {
    final changes = <String>[
      if (next.weights.join() != settings.weights.join()) 'น้ำหนักปัจจัย AI ${next.weights.join('/')}',
      if (next.balancedCap != settings.balancedCap) 'เวลาสูงสุดต่องาน ${next.balancedCap} นาที',
      if (next.aiTimeoutSeconds != settings.aiTimeoutSeconds) 'เวลารอ AI ${next.aiTimeoutSeconds} วินาที',
      if (next.fallbackPlan != settings.fallbackPlan) 'แผนสำรอง ${next.fallbackPlan ? 'เปิด' : 'ปิด'}',
      if (next.reminderMinutes != settings.reminderMinutes) 'แจ้งเตือนก่อน ${next.reminderMinutes} นาที',
      if (next.passwordMinLength != settings.passwordMinLength) 'รหัสผ่านขั้นต่ำ ${next.passwordMinLength} ตัว',
      if (next.dataRetentionDays != settings.dataRetentionDays) 'เก็บประวัติ ${next.dataRetentionDays} วัน',
      if (next.maintenanceMode != settings.maintenanceMode) 'โหมดปิดปรับปรุง ${next.maintenanceMode ? 'เปิด' : 'ปิด'}',
    ];
    settings = next;
    lastResult = null; // น้ำหนักเปลี่ยน ต้องวิเคราะห์ใหม่
    logs.insert(
      0,
      SystemLog(
        time: DateTime.now(),
        service: 'ตั้งค่าระบบ',
        level: 'Info',
        detail: changes.isEmpty ? 'บันทึกการตั้งค่า (ไม่มีการเปลี่ยนแปลง)' : 'ผู้ดูแลปรับ: ${changes.join(', ')}',
        status: 'ปกติ',
      ),
    );
    notifyListeners();
  }

  void resolveLog(SystemLog l) {
    l.status = 'แก้ไขแล้ว';
    notifyListeners();
  }

  void refreshStatus() {
    statusRefreshedAt = DateTime.now();
    notifyListeners();
  }

  void restartAi() {
    aiHealthy = true;
    aiLatency.add(1.9);
    if (aiLatency.length > 12) aiLatency.removeAt(0);
    for (final l in logs) {
      if (l.service == 'AI Service Provider' && l.pending) l.status = 'แก้ไขแล้ว';
    }
    logs.insert(0, SystemLog(time: DateTime.now(), service: 'AI Service Provider', level: 'Info', detail: 'รีสตาร์ตบริการสำเร็จ · เวลาตอบสนองกลับสู่ปกติ', status: 'ปกติ'));
    statusRefreshedAt = DateTime.now();
    notifyListeners();
  }

  // ------------------------------------------------------ บันทึกลงเครื่อง
  Timer? _saveTimer;

  @override
  void notifyListeners() {
    super.notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    if (!Storage.ready) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () => Storage.save(toJson()));
  }

  /// เรียกครั้งเดียวตอนเปิดแอป (ใน main.dart) เพื่อโหลดข้อมูลที่บันทึกไว้
  Future<void> init() async {
    try {
      await Storage.init();
    } catch (_) {
      return; // บันทึกไม่ได้ (เช่น เบราว์เซอร์ปิด storage) — ใช้งานต่อได้แบบไม่บันทึก
    }
    final data = Storage.load();
    if (data != null) _restore(data);
    _rollOverDay();
    await Storage.save(toJson());
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'demoMode': demoMode,
        'rememberLogin': rememberLogin,
        'userName': userName,
        'email': email,
        'joined': joined.toIso8601String(),
        'activities': activities.map(activityToJson).toList(),
        'slots': [for (final t in slots) [t.start, t.end]],
        'allGoals': allGoals,
        'goals': goals,
        'activeDays': activeDays.toList(),
        'excludedFromAi': excludedFromAi.toList(),
        'aiNote': aiNote,
        'plan': plan.map(blockToJson).toList(),
        'planCode': planCode,
        'planAdjusted': planAdjusted,
        'planConfirmedAt': planConfirmedAt?.toIso8601String(),
        'planDate': planDate?.toIso8601String(),
        'history': history.map(historyToJson).toList(),
        'notices': notices.map(noticeToJson).toList(),
        'postponeCounts': postponeCounts,
        'notifyBefore': notifyBefore,
        'notifyChange': notifyChange,
        'notifyLog': notifyLog,
        'aiLearn': aiLearn,
        'settings': settingsToJson(settings),
        'logs': logs.map(logToJson).toList(),
      };

  void _restore(Map<String, dynamic> j) {
    try {
      demoMode = (j['demoMode'] as bool?) ?? true;
      rememberLogin = (j['rememberLogin'] as bool?) ?? false;
      userName = (j['userName'] as String?) ?? userName;
      email = (j['email'] as String?) ?? email;
      joined = DateTime.tryParse((j['joined'] as String?) ?? '') ?? joined;
      activities
        ..clear()
        ..addAll(decodeList(j['activities'], activityFromJson));
      final rawSlots = j['slots'];
      if (rawSlots is List) {
        slots
          ..clear()
          ..addAll([
            for (final t in rawSlots)
              if (t is List && t.length == 2) TimeSlot(t[0] as int, t[1] as int),
          ]);
      }
      final ag = j['allGoals'];
      if (ag is List) {
        allGoals
          ..clear()
          ..addAll(ag.whereType<String>());
      }
      final g = j['goals'];
      if (g is List) {
        goals
          ..clear()
          ..addAll(g.whereType<String>());
      }
      final days = j['activeDays'];
      if (days is List) {
        activeDays
          ..clear()
          ..addAll(days.whereType<int>());
      }
      final ex = j['excludedFromAi'];
      excludedFromAi
        ..clear()
        ..addAll(ex is List ? ex.whereType<String>() : const <String>[]);
      aiNote = (j['aiNote'] as String?) ?? '';
      plan = decodeList(j['plan'], blockFromJson);
      planCode = j['planCode'] as String?;
      planAdjusted = (j['planAdjusted'] as bool?) ?? false;
      planConfirmedAt = DateTime.tryParse((j['planConfirmedAt'] as String?) ?? '');
      planDate = DateTime.tryParse((j['planDate'] as String?) ?? '');
      history
        ..clear()
        ..addAll(decodeList(j['history'], historyFromJson));
      notices
        ..clear()
        ..addAll(decodeList(j['notices'], noticeFromJson));
      postponeCounts.clear();
      final pc = j['postponeCounts'];
      if (pc is Map) {
        pc.forEach((k, v) {
          if (k is String && v is int) postponeCounts[k] = v;
        });
      }
      notifyBefore = (j['notifyBefore'] as bool?) ?? true;
      notifyChange = (j['notifyChange'] as bool?) ?? true;
      notifyLog = (j['notifyLog'] as bool?) ?? false;
      aiLearn = (j['aiLearn'] as bool?) ?? true;
      final st = j['settings'];
      if (st is Map) settings = settingsFromJson(Map<String, dynamic>.from(st));
      final lg = decodeList(j['logs'], logFromJson);
      if (lg.isNotEmpty) {
        logs
          ..clear()
          ..addAll(lg);
      }
    } catch (_) {
      // ถ้าข้อมูลบางส่วนอ่านไม่ได้ ใช้ค่าที่อ่านได้แล้วต่อไป
    }
  }

  /// ขึ้นวันใหม่: ล้างแผนของเมื่อวาน และรีเซ็ตกิจกรรมประจำวันให้กลับมาเป็น "ยังไม่เสร็จ"
  void _rollOverDay() {
    final pd = planDate;
    if (pd != null && daysBetween(pd, now) != 0) {
      if (history.isNotEmpty && history.first.result == 'กำลังดำเนินการ') {
        final ids = plan.map((b) => b.activityId).toSet();
        final done = ids.where((id) => byId(id)?.status == ActivityStatus.done).length;
        final h = history.first;
        history[0] = HistoryEntry(time: h.time, kind: h.kind, title: h.title, detail: h.detail, result: 'สำเร็จ $done/${ids.length}', optionCode: h.optionCode);
      }
      plan = [];
      planCode = null;
      planAdjusted = false;
      planConfirmedAt = null;
      planDate = null;
      lastResult = null;
    }
    for (final a in activities.where((a) => a.recurring)) {
      if (daysBetween(a.deadline, now) > 0 || (a.status == ActivityStatus.done && a.completedAt != null && daysBetween(a.completedAt!, now) > 0)) {
        a.deadline = DateTime(now.year, now.month, now.day, a.deadline.hour, a.deadline.minute);
        if (a.status == ActivityStatus.done) {
          a.status = ActivityStatus.todo;
          a.actualMinutes = null;
          a.feedbackGood = null;
          a.feedbackNote = '';
          a.completedAt = null;
        }
      }
    }
  }

  void _clearUserData() {
    activities.clear();
    history.clear();
    notices.clear();
    postponeCounts.clear();
    excludedFromAi.clear();
    plan = [];
    planCode = null;
    planAdjusted = false;
    planConfirmedAt = null;
    planDate = null;
    lastResult = null;
    aiNote = '';
  }

  /// เริ่มใช้งานจริง: ล้างข้อมูลตัวอย่างทั้งหมด เหลือเฉพาะข้อมูลของผู้ใช้
  void startFresh({String? name, String? mail}) {
    _clearUserData();
    if (name != null && name.trim().isNotEmpty) userName = name.trim();
    if (mail != null && mail.trim().isNotEmpty) email = mail.trim();
    joined = DateTime.now();
    demoMode = false;
    notices.add(AppNotice(
      kind: NoticeKind.report,
      title: 'ยินดีต้อนรับสู่ TimeWise AI',
      body: 'เริ่มจากเพิ่มกิจกรรมในแท็บ “กิจกรรม” แล้วกดปุ่ม ถาม AI เพื่อให้ระบบช่วยจัดสรรเวลา',
      time: DateTime.now(),
      route: 'tab:1',
    ));
    notifyListeners();
  }

  /// โหลดข้อมูลตัวอย่างกลับมา (ใช้ตอนอัดวิดีโอสาธิต)
  void loadDemo() {
    _clearUserData();
    logs.clear();
    users.clear();
    userName = 'มิว';
    email = 'mew.student@example.com';
    joined = DateTime.now().subtract(const Duration(days: 20));
    slots
      ..clear()
      ..addAll(const [TimeSlot(13 * 60, 15 * 60), TimeSlot(18 * 60, 21 * 60)]);
    goals
      ..clear()
      ..addAll(['เตรียมสอบ', 'ส่งงานตรงเวลา']);
    aiNote = 'ช่วงเย็นมักเหนื่อย อยากทำงานที่ใช้สมาธิสูงช่วงบ่าย';
    demoMode = true;
    _seed();
    notifyListeners();
  }

  /// ลบข้อมูลทั้งหมดในเครื่อง แล้วเริ่มเหมือนติดตั้งใหม่
  Future<void> wipeAll() async {
    await Storage.clear();
    rememberLogin = false;
    settings = SystemSettings();
    loadDemo();
  }

  void setRememberLogin(bool v) {
    rememberLogin = v;
    notifyListeners();
  }

  void logout() {
    rememberLogin = false;
    homeTab.value = 0;
    notifyListeners();
  }

  // --------------------------------------------------------- ข้อมูลตัวอย่าง
  void _seed() {
    activities.addAll([
      Activity(id: 'a1', name: 'อ่านหนังสือสอบ SA', type: ActivityType.study, minutes: 120, deadline: at(1, 9, 0), priority: Priority.high, goal: 'เตรียมสอบ', note: 'บทที่ 5–7 และ Use Case / Sequence Diagram'),
      Activity(id: 'a2', name: 'ทำรายงาน SA ครั้งที่ 3', type: ActivityType.study, minutes: 180, deadline: at(4, 23, 59), priority: Priority.high, goal: 'ส่งงานตรงเวลา', status: ActivityStatus.inProgress),
      Activity(id: 'a3', name: 'เตรียมสไลด์ประชุมกลุ่ม', type: ActivityType.work, minutes: 60, deadline: at(2, 10, 0), priority: Priority.medium, goal: 'ส่งงานตรงเวลา'),
      Activity(id: 'a4', name: 'ทบทวน Data Structure', type: ActivityType.study, minutes: 90, deadline: at(6, 13, 0), priority: Priority.medium, goal: 'เตรียมสอบ'),
      Activity(id: 'a5', name: 'ออกกำลังกาย', type: ActivityType.health, minutes: 60, deadline: at(0, 21, 0), priority: Priority.medium, goal: 'ดูแลสุขภาพ', recurring: true),
      Activity(id: 'a6', name: 'ซักผ้าและจัดห้อง', type: ActivityType.personal, minutes: 30, deadline: at(3, 18, 0), priority: Priority.low),
      // กิจกรรมที่ทำเสร็จแล้ว (ใช้แสดงรายงานสรุปและประวัติการใช้เวลา)
      Activity(id: 'd1', name: 'ส่งการบ้าน Calculus', type: ActivityType.study, minutes: 60, deadline: at(-1, 23, 59), priority: Priority.high, goal: 'ส่งงานตรงเวลา', status: ActivityStatus.done, actualMinutes: 70, feedbackGood: true, completedAt: at(-1, 20, 30)),
      Activity(id: 'd2', name: 'อ่านชีท Database', type: ActivityType.study, minutes: 90, deadline: at(-2, 23, 59), priority: Priority.medium, goal: 'เตรียมสอบ', status: ActivityStatus.done, actualMinutes: 110, feedbackGood: true, completedAt: at(-2, 15, 0)),
      Activity(id: 'd3', name: 'ทำ Lab Network', type: ActivityType.work, minutes: 120, deadline: at(-2, 23, 59), priority: Priority.high, goal: 'ส่งงานตรงเวลา', status: ActivityStatus.done, actualMinutes: 130, feedbackGood: true, completedAt: at(-2, 21, 0)),
      Activity(id: 'd4', name: 'วิ่งรอบสวน', type: ActivityType.health, minutes: 60, deadline: at(-3, 20, 0), priority: Priority.medium, goal: 'ดูแลสุขภาพ', status: ActivityStatus.done, actualMinutes: 45, feedbackGood: true, completedAt: at(-3, 19, 0)),
      Activity(id: 'd5', name: 'ทำความสะอาดห้อง', type: ActivityType.personal, minutes: 45, deadline: at(-4, 20, 0), priority: Priority.low, status: ActivityStatus.done, actualMinutes: 60, feedbackGood: false, feedbackNote: 'ไม่มีเวลาพัก', completedAt: at(-4, 20, 0)),
      Activity(id: 'd6', name: 'ประชุมชมรม', type: ActivityType.work, minutes: 60, deadline: at(-3, 18, 0), priority: Priority.medium, status: ActivityStatus.done, actualMinutes: 60, feedbackGood: true, completedAt: at(-3, 18, 0)),
    ]);

    postponeCounts.addAll({'ออกกำลังกาย': 3, 'ทบทวน Data Structure': 1, 'ซักผ้าและจัดห้อง': 1});

    history.addAll([
      HistoryEntry(time: at(-1, 11, 45), kind: DecisionKind.accepted, title: 'ทางเลือก C · เน้นความสมดุล', detail: 'เสร็จ 3 จาก 4 งาน · ใช้เวลาจริงเกินแผน 20 นาที · Feedback: เหมาะสม', result: 'สำเร็จ 3/4', optionCode: 'C'),
      HistoryEntry(time: at(-2, 12, 30), kind: DecisionKind.rejected, title: 'ปฏิเสธคำแนะนำ · จัดเอง', detail: 'เหตุผล: มีนัดประชุมกลุ่มที่ไม่ได้บันทึกในระบบ', result: 'สำเร็จ 2/3'),
      HistoryEntry(time: at(-3, 8, 20), kind: DecisionKind.accepted, title: 'ทางเลือก B · เน้นเป้าหมาย', detail: 'เสร็จ 3 จาก 3 งาน · Feedback: เหมาะสม', result: 'สำเร็จ 3/3', optionCode: 'B'),
      HistoryEntry(time: at(-4, 10, 5), kind: DecisionKind.adjusted, title: 'ทางเลือก A · เน้น Deadline (ปรับเอง)', detail: 'เสร็จ 2 จาก 2 งาน · Feedback: ไม่เหมาะสม (ไม่มีเวลาพัก)', result: 'สำเร็จ 2/2', optionCode: 'A'),
    ]);

    notices.addAll([
      AppNotice(kind: NoticeKind.deadline, title: 'Deadline ใกล้ถึง', body: '“อ่านหนังสือสอบ SA” ครบกำหนดพรุ่งนี้ 09:00 น.', time: at(0, 8, 0), route: 'tab:1'),
      AppNotice(kind: NoticeKind.logResult, title: 'อย่าลืมบันทึกผล', body: 'บันทึกเวลาที่ใช้จริงหลังทำกิจกรรม เพื่อให้คำแนะนำแม่นยำขึ้น', time: at(-1, 21, 5), unread: false, route: 'tab:2'),
      AppNotice(kind: NoticeKind.report, title: 'สรุปรายสัปดาห์พร้อมแล้ว', body: 'ดูรายงานสรุปการใช้เวลาและกิจกรรมที่ถูกเลื่อนบ่อย', time: at(-1, 20, 0), unread: false, route: 'tab:3'),
    ]);

    logs.addAll([
      SystemLog(time: at(0, 16, 12), service: 'AI Service Provider', level: 'Warning', detail: 'เวลาตอบสนองเกิน 4 วินาที (4.6 s) ต่อเนื่อง 15 นาที'),
      SystemLog(time: at(0, 15, 48), service: 'AI Service Provider', level: 'Error', detail: 'Request timeout เกินเวลาที่กำหนด · แสดงแผนสำรองตาม Deadline ให้ผู้ใช้ 3 ราย'),
      SystemLog(time: at(0, 11, 5), service: 'Notification Service', level: 'Warning', detail: 'ส่งการแจ้งเตือนล่าช้า 2 นาที (คิวสะสม 120 รายการ)', status: 'แก้ไขแล้ว'),
      SystemLog(time: at(0, 8, 30), service: 'Database Server', level: 'Info', detail: 'สำรองข้อมูลอัตโนมัติสำเร็จ (PostgreSQL · 1.2 GB)', status: 'ปกติ'),
      SystemLog(time: at(-1, 22, 40), service: 'Application Server', level: 'Error', detail: 'หน่วยความจำใช้เกิน 90% ชั่วคราว ระบบรีสตาร์ต worker อัตโนมัติ', status: 'แก้ไขแล้ว'),
      SystemLog(time: at(-1, 9, 15), service: 'Application Server', level: 'Warning', detail: 'ผู้ใช้เข้าสู่ระบบผิดพลาดติดกัน 5 ครั้ง (kan.p@example.com) ระบบล็อกบัญชีชั่วคราว'),
      SystemLog(time: at(-2, 8, 30), service: 'Database Server', level: 'Info', detail: 'สำรองข้อมูลอัตโนมัติสำเร็จ (PostgreSQL · 1.2 GB)', status: 'ปกติ'),
    ]);

    users.addAll([
      AppUser(name: 'มิว', email: 'mew.student@example.com', joined: at(-20, 9, 0), lastActive: 'วันนี้'),
      AppUser(name: 'ต้นกล้า', email: 'tonkla@example.com', joined: at(-19, 10, 0), lastActive: 'วันนี้'),
      AppUser(name: 'ปาล์ม', email: 'palm.s@example.com', joined: at(-18, 11, 0), lastActive: 'เมื่อวาน'),
      AppUser(name: 'ใบเตย', email: 'baitoey@example.com', joined: at(-16, 12, 0), lastActive: '3 วันก่อน'),
      AppUser(name: 'กันต์', email: 'kan.p@example.com', joined: at(-14, 13, 0), lastActive: '9 วันก่อน', status: 'ระงับ'),
      AppUser(name: 'ฟ้าใส', email: 'fahsai@example.com', joined: at(-13, 14, 0), lastActive: '2 วันก่อน'),
      AppUser(name: 'ภูมิ', email: 'phum.t@example.com', joined: at(-9, 15, 0), lastActive: 'ยังไม่เคยเข้าใช้', status: 'รอยืนยันอีเมล'),
    ]);
  }
}
