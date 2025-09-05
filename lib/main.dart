import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:vibration/vibration.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  runApp(const ScareRotationsApp());
}

class ScareRotationsApp extends StatelessWidget {
  const ScareRotationsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Scare Rotations',
      theme: ThemeData.dark(),
      home: const RotationScreen(),
    );
  }
}

// ---------------- ENUM + DATA ----------------
enum Status { onSet, offSet, meal }

class Slot {
  final DateTime start;
  final DateTime end;
  final Status a, b, c;
  const Slot({
    required this.start,
    required this.end,
    required this.a,
    required this.b,
    required this.c,
  });
}

// ---------------- MAIN SCREEN ----------------
class RotationScreen extends StatefulWidget {
  const RotationScreen({super.key});
  @override
  State<RotationScreen> createState() => _RotationScreenState();
}

class _RotationScreenState extends State<RotationScreen> {
  final _notifier = FlutterLocalNotificationsPlugin();
  late List<Slot> _today;
  Timer? _ticker;
  Slot? _lastSlot;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _buildToday();
    _startTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // ---------- Notifications ----------
  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _notifier.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    await _notifier
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _notifier
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    const channel = AndroidNotificationChannel(
      'rotations',
      'Rotations',
      description: '20-minute rotation alerts',
      importance: Importance.high,
      enableVibration: true,
    );
    await _notifier
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _scheduleAllNotifications() async {
    await _notifier.cancelAll();
    for (final s in _today) {
      if (s.start.isAfter(DateTime.now())) {
        final body = _lineForSlot(s);
        await _notifier.zonedSchedule(
          s.start.millisecondsSinceEpoch ~/ 1000,
          'Rotation',
          body,
          tz.TZDateTime.from(s.start, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'rotations',
              'Rotations',
              channelDescription: '20-minute rotation alerts',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }

  // ---------- Schedule ----------
  void _buildToday() {
    DateTime t(int hour12, int minute, bool isPm) {
      final now = DateTime.now();
      int hour24 = hour12 % 12 + (isPm ? 12 : 0);
      if (hour12 == 12 && !isPm) hour24 = 0;   // 12 AM
      if (hour12 == 12 && isPm) hour24 = 12;   // 12 PM
      return DateTime(now.year, now.month, now.day, hour24, minute);
    }

    Slot s(DateTime start, Status a, Status b, Status c) =>
        Slot(start: start, end: start.add(const Duration(minutes: 20)), a: a, b: b, c: c);

    _today = [
      s(t(7, 00, true), Status.onSet, Status.onSet, Status.offSet),
      s(t(7, 20, true), Status.onSet, Status.offSet, Status.onSet),
      s(t(7, 40, true), Status.meal, Status.onSet, Status.onSet),
      s(t(8, 00, true), Status.meal, Status.onSet, Status.onSet),
      s(t(8, 20, true), Status.onSet, Status.onSet, Status.offSet),
      s(t(8, 40, true), Status.onSet, Status.meal, Status.onSet),
      s(t(9, 00, true), Status.onSet, Status.meal, Status.onSet),
      s(t(9, 20, true), Status.offSet, Status.onSet, Status.onSet),
      s(t(9, 40, true), Status.onSet, Status.onSet, Status.meal),
      s(t(10, 00, true), Status.onSet, Status.onSet, Status.meal),
      s(t(10, 20, true), Status.onSet, Status.offSet, Status.onSet),
      s(t(10, 40, true), Status.offSet, Status.onSet, Status.onSet),
      s(t(11, 00, true), Status.onSet, Status.onSet, Status.offSet),
      s(t(11, 20, true), Status.onSet, Status.offSet, Status.onSet),
      s(t(11, 40, true), Status.offSet, Status.onSet, Status.onSet),
      s(t(12, 00, false), Status.onSet, Status.onSet, Status.offSet),
      s(t(12, 20, false), Status.onSet, Status.offSet, Status.onSet),
      s(t(12, 40, false), Status.offSet, Status.onSet, Status.onSet),
      s(t(1, 00, false), Status.offSet, Status.offSet, Status.offSet),
    ];
  }

  // ---------- Ticker ----------
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final now = DateTime.now();
      final current = _currentSlot(now);
      if (current != null && current != _lastSlot) {
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 200);
        }
        _lastSlot = current;
      }
      setState(() {});
    });
  }

  Slot? _currentSlot(DateTime now) {
    for (final s in _today) {
      if (!now.isBefore(s.start) && now.isBefore(s.end)) return s;
    }
    return null;
  }

  Slot? _nextBoundary(DateTime now) {
    for (final s in _today) {
      if (s.start.isAfter(now)) return s;
    }
    return null;
  }

  // ---------- Rendering Helpers ----------
  String _namesWith(Status st, Slot s) {
    final names = <String>[];
    if (s.a == st) names.add('A');
    if (s.b == st) names.add('B');
    if (s.c == st) names.add('C');
    return names.join(' & ');
  }

  String _lineForSlot(Slot s) {
    final on = _namesWith(Status.onSet, s);
    final meal = _namesWith(Status.meal, s);
    final off = _namesWith(Status.offSet, s);

    final bits = <String>[];
    if (on.isNotEmpty) bits.add('$on ON SET');
    if (meal.isNotEmpty) bits.add('$meal on Meal');
    if (off.isNotEmpty) bits.add('$off Off Set');
    return bits.join(' · ');
  }

  Widget _statusLine(String label, Status st, Slot slot) {
    final names = _namesWith(st, slot);
    if (names.isEmpty) return const SizedBox.shrink();
    return Text('$names on $label', style: const TextStyle(fontSize: 20));
  }

  String _pretty(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  // -------- Pre/Post-show helpers --------
  // Treat 12:00–1:59 AM as “last night” so the anchors (6, 7 PM, 1 AM) make sense after midnight
  DateTime _eventDayAt(int hour24, int minute) {
    var now = DateTime.now();
    if (now.hour < 2) now = now.subtract(const Duration(days: 1));
    return DateTime(now.year, now.month, now.day, hour24, minute);
  }

  String _prettyHMS(Duration d) {
    final total = d.inSeconds;
    if (total <= 0) return '00:00';
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return h > 0
        ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final callTime = _eventDayAt(18, 0); // 6:00 PM
    final startTime = _eventDayAt(19, 0); // 7:00 PM
    final endTime   = _eventDayAt(1, 0);  // 1:00 AM (end of show)

    final slot = _currentSlot(now);
    final next = _nextBoundary(now);
    final timeFmt = DateFormat.jm();

    Widget preShow() {
      if (now.isBefore(callTime)) {
        final remaining = callTime.difference(now);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Be at venue in', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            Text(_prettyHMS(remaining),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Call time: ${timeFmt.format(callTime)}',
                style: const TextStyle(color: Colors.grey)),
          ],
        );
      } else if (now.isBefore(startTime)) {
        final remaining = startTime.difference(now);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Event starts in', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            Text(_prettyHMS(remaining),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Show time: ${timeFmt.format(startTime)}',
                style: const TextStyle(color: Colors.grey)),
          ],
        );
      }
      return const SizedBox.shrink();
    }

    Widget postShow() {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Text(
            'Event closed! Great job everyone!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          Text(
            'FEED THE FEAR!! NOURISH THE TERROR!!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('HOS Rotations'),
        actions: [
          IconButton(
            tooltip: 'Arm notifications',
            onPressed: () async {
              await _scheduleAllNotifications();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notifications scheduled.')),
                );
              }
            },
            icon: const Icon(Icons.notifications_active_outlined),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: now.isAfter(endTime)
              ? postShow()                         // after 1:00 AM
              : now.isBefore(startTime)
                  ? preShow()                      // before 7:00 PM
                  : (slot == null                  // 7:00 PM–1:00 AM
                      ? const Text('No active slot right now',
                          style: TextStyle(fontSize: 20))
                      : Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Text(
                              '${timeFmt.format(slot.start)} – ${timeFmt.format(slot.end)}',
                              style: const TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _namesWith(Status.onSet, slot).isEmpty
                                  ? 'No one is on set'
                                  : '${_namesWith(Status.onSet, slot)} are ON SET',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 28, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            _statusLine('Meal', Status.meal, slot),
                            _statusLine('Off Set', Status.offSet, slot),
                            const SizedBox(height: 30),
                            Text(
                              'Next rotation in ${_pretty(slot.end.difference(now))}',
                              style: const TextStyle(fontSize: 18),
                            ),
                            if (next != null)
                              Text('Next starts at ${timeFmt.format(next.start)}'),
                          ],
                        )),
        ),
      ),
    );
  }
}
