// ignore_for_file: unused_local_variable

import 'dart:async';

import 'package:achievr_app/Screens/habit_log_service.dart';
import 'package:achievr_app/Services/app_clock.dart';
import 'package:achievr_app/Widgets/hold_to_refresh_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final HabitLogService _habitLogService = HabitLogService();

  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> todayLogs = [];

  bool _isLoading = true;
  bool _isUpdatingLog = false;
  String? _error;

  Timer? _clockTimer;

  static const Duration _gracePeriod = Duration(minutes: 30);
  static const Duration _startsSoonThreshold = Duration(minutes: 60);

  DateTime get _screenNow => AppClock.now();
  DateTime get _screenToday => AppClock.today();

  @override
  void initState() {
    super.initState();
    _loadTodayData();

    AppClock.debugNowNotifier.addListener(_handleClockChange);

    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _handleClockChange() {
    if (!mounted) return;
    _loadTodayData();
  }

  @override
  void dispose() {
    AppClock.debugNowNotifier.removeListener(_handleClockChange);
    _clockTimer?.cancel();
    super.dispose();
  }

  int _timeToMinutes(String? hhmmss) {
    if (hhmmss == null || hhmmss.isEmpty) return 999999;

    final parts = hhmmss.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    return (hour * 60) + minute;
  }

  int _compareLogsByStartTime(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final aMinutes = _timeToMinutes(a['scheduled_start']?.toString());
    final bMinutes = _timeToMinutes(b['scheduled_start']?.toString());

    if (aMinutes != bMinutes) {
      return aMinutes.compareTo(bMinutes);
    }

    final aEnd = _timeToMinutes(a['scheduled_end']?.toString());
    final bEnd = _timeToMinutes(b['scheduled_end']?.toString());

    return aEnd.compareTo(bEnd);
  }

  Future<void> _loadTodayData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        if (!mounted) return;
        setState(() {
          _error = 'No authenticated user found.';
          _isLoading = false;
        });
        return;
      }

      final profileResponse = await supabase
          .from('profiles')
          .select('username, strict_mode_enabled, plan_tier')
          .eq('id', user.id)
          .maybeSingle();

      await _habitLogService.generateTodayLogs();

      final logs = await _habitLogService.fetchTodayLogs()
        ..sort(_compareLogsByStartTime);

      if (!mounted) return;

      setState(() {
        profile = profileResponse;
        todayLogs = logs;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('TODAY SCREEN ERROR: $e');
      debugPrint('$st');

      if (!mounted) return;

      setState(() {
        _error = 'Failed to load today screen:\n$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _markLogDone(Map<String, dynamic> log) async {
    final logId = log['log_id']?.toString();
    if (logId == null || logId.isEmpty) return;

    final availability = _manualCompletionAvailability(log);
    if (!availability.canCompleteNow) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(availability.message)),
      );
      return;
    }

    try {
      setState(() {
        _isUpdatingLog = true;
      });

      await _habitLogService.markLogDone(logId: logId);
      await _loadTodayData();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Habit marked as done.')),
      );
    } catch (e) {
      debugPrint('MARK LOG DONE ERROR: $e');

      if (!mounted) return;

      setState(() {
        _isUpdatingLog = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to mark habit as done.')),
      );
    }
  }

  String get _username {
    final username = profile?['username'];
    if (username is String && username.trim().isNotEmpty) {
      return username.trim();
    }
    return 'User';
  }

  String get _todayLabel {
    const dayNames = [
      '',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return dayNames[_screenToday.weekday];
  }

  String _formatDate(DateTime dt) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month]} ${dt.day}';
  }

  String _formatTimeString(String hhmmss) {
    final parts = hhmmss.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    final suffix = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : hour > 12 ? hour - 12 : hour;
    final minuteText = minute.toString().padLeft(2, '0');

    return '$displayHour:$minuteText $suffix';
  }

  DateTime? _logStartDateTime(Map<String, dynamic> log) {
    final timeString = log['scheduled_start']?.toString();
    if (timeString == null || timeString.isEmpty) return null;

    final parts = timeString.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;

    return DateTime(
      _screenToday.year,
      _screenToday.month,
      _screenToday.day,
      hour,
      minute,
    );
  }

  DateTime? _logEndDateTime(Map<String, dynamic> log) {
    final timeString = log['scheduled_end']?.toString();
    if (timeString == null || timeString.isEmpty) return null;

    final parts = timeString.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;

    return DateTime(
      _screenToday.year,
      _screenToday.month,
      _screenToday.day,
      hour,
      minute,
    );
  }

  _CompletionAvailability _manualCompletionAvailability(
    Map<String, dynamic> log,
  ) {
    final start = _logStartDateTime(log);
    final end = _logEndDateTime(log);

    if (start == null || end == null) {
      return const _CompletionAvailability(
        canCompleteNow: true,
        message: 'No strict execution window for this task.',
      );
    }

    final now = _screenNow;
    final latestAllowed = end.add(_gracePeriod);

    if (now.isBefore(start)) {
      return _CompletionAvailability(
        canCompleteNow: false,
        message:
            'This task becomes available at ${_formatTimeString(log['scheduled_start'].toString())}.',
      );
    }

    if (now.isAfter(latestAllowed)) {
      final expiredAt = _formatTimeString(
        '${latestAllowed.hour.toString().padLeft(2, '0')}:${latestAllowed.minute.toString().padLeft(2, '0')}:00',
      );

      return _CompletionAvailability(
        canCompleteNow: false,
        message: 'This task expired at $expiredAt.',
      );
    }

    return const _CompletionAvailability(
      canCompleteNow: true,
      message: 'Task can be completed now.',
    );
  }

  String _taskState(Map<String, dynamic> log) {
    final rawStatus = (log['status'] ?? 'pending').toString();
    if (rawStatus == 'done') return 'done';

    final start = _logStartDateTime(log);
    final end = _logEndDateTime(log);

    if (start == null || end == null) return 'available';

    final now = _screenNow;
    final latestAllowed = end.add(_gracePeriod);

    if (now.isAfter(latestAllowed)) return 'missed';
    if (!now.isBefore(start) && !now.isAfter(latestAllowed)) return 'available';

    final untilStart = start.difference(now);
    if (!untilStart.isNegative && untilStart <= _startsSoonThreshold) {
      return 'soon';
    }

    return 'upcoming';
  }

  String _taskStateLabel(String state) {
    switch (state) {
      case 'done':
        return 'Done';
      case 'available':
        return 'Available now';
      case 'soon':
        return 'Starts soon';
      case 'upcoming':
        return 'Upcoming';
      case 'missed':
        return 'Missed';
      default:
        return 'Pending';
    }
  }

  Color _taskStateTextColor(String state) {
    switch (state) {
      case 'done':
        return Colors.greenAccent;
      case 'available':
        return const Color(0xFFF5F5F5);
      case 'soon':
        return const Color(0xFFFFD166);
      case 'upcoming':
        return const Color(0xFFB3B3BB);
      case 'missed':
        return const Color(0xFFFF8A80);
      default:
        return const Color(0xFFB3B3BB);
    }
  }

  Color _taskStateBorderColor(String state) {
    switch (state) {
      case 'done':
        return const Color(0xFF2E7D32);
      case 'available':
        return const Color(0xFFF5F5F5);
      case 'soon':
        return const Color(0xFFFFD166);
      case 'upcoming':
        return const Color(0xFF3A3A42);
      case 'missed':
        return const Color(0xFFE57373);
      default:
        return const Color(0xFF232329);
    }
  }

  Color _taskStateBackgroundColor(String state) {
    switch (state) {
      case 'done':
        return const Color(0x142E7D32);
      case 'available':
        return const Color(0x22F5F5F5);
      case 'soon':
        return const Color(0x22FFD166);
      case 'upcoming':
        return const Color(0xFF101013);
      case 'missed':
        return const Color(0x22E57373);
      default:
        return const Color(0xFF101013);
    }
  }

  List<Map<String, dynamic>> get _availableLogs => todayLogs
      .where((log) => _taskState(log) == 'available')
      .toList()
    ..sort(_compareLogsByStartTime);

  List<Map<String, dynamic>> get _completedLogs => todayLogs
      .where((log) => _taskState(log) == 'done')
      .toList()
    ..sort(_compareLogsByStartTime);

  List<Map<String, dynamic>> get _missedLogs => todayLogs
      .where((log) => _taskState(log) == 'missed')
      .toList()
    ..sort(_compareLogsByStartTime);

  Map<String, dynamic>? get _nextTask {
    final pendingLogs = todayLogs
        .where((log) => (log['status'] ?? 'pending').toString() != 'done')
        .toList()
      ..sort(_compareLogsByStartTime);

    for (final log in pendingLogs) {
      final state = _taskState(log);
      if (state == 'soon' || state == 'upcoming') {
        return log;
      }
    }

    return null;
  }

  String _timeUntil(DateTime start) {
    final now = _screenNow;
    final difference = start.difference(now);

    if (difference.isNegative) {
      return 'In progress or due now';
    }

    final hours = difference.inHours;
    final minutes = difference.inMinutes % 60;

    if (hours > 0) {
      return 'Starts in ${hours}h ${minutes}m';
    }

    if (minutes > 0) {
      return 'Starts in ${minutes}m';
    }

    return 'Starting now';
  }

  String _nextTaskMessage(Map<String, dynamic> log) {
    final state = _taskState(log);
    final start = _logStartDateTime(log);

    if (state == 'soon' || state == 'upcoming') {
      return start != null ? _timeUntil(start) : 'Scheduled for later today';
    }

    if (state == 'missed') {
      return 'This task was missed. Recover the next available commitment.';
    }

    return 'Scheduled for today';
  }

  int get _doneCount => _completedLogs.length;
  int get _pendingCount =>
      todayLogs.where((log) => _taskState(log) != 'done').length;

  Widget _buildMetricChip({
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _taskStateBackgroundColor(state),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _taskStateBorderColor(state)),
      ),
      child: Text(
        _taskStateLabel(state),
        style: TextStyle(
          color: _taskStateTextColor(state),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildTopHero() {
    final strictMode = profile?['strict_mode_enabled'] == true;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$_todayLabel • ${_formatDate(_screenToday)}',
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Welcome back, $_username',
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            strictMode
                ? 'Today is execution day. Complete what is scheduled and protect momentum.'
                : 'Stay consistent today. Focus on the next right action.',
            style: const TextStyle(
              color: Color(0xFFB3B3BB),
              height: 1.45,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildMetricChip(
                  label: 'Today',
                  value: '${todayLogs.length}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Done',
                  value: '$_doneCount',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Pending',
                  value: '$_pendingCount',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNextTaskCard() {
    final nextTask = _nextTask;

    if (nextTask == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF17171A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF232329)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(
              'Next task',
              subtitle: 'Your next scheduled commitment.',
            ),
            const Text(
              'No upcoming tasks remain for today.',
              style: TextStyle(
                color: Color(0xFFB3B3BB),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    final habit = nextTask['habits'] as Map<String, dynamic>?;
    final goal = habit?['goals'] as Map<String, dynamic>?;
    final verificationType =
        (nextTask['verification_type'] ?? 'manual').toString();
    final state = _taskState(nextTask);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF17171A),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _taskStateBorderColor(state)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(
              'Next task',
              subtitle: 'Your next scheduled commitment.',
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    habit?['title']?.toString() ?? 'Untitled Habit',
                    style: const TextStyle(
                      color: Color(0xFFF5F5F5),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _buildStatusChip(state),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              goal?['title']?.toString() ?? 'Unknown Goal',
              style: const TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101013),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF232329)),
                  ),
                  child: Text(
                    nextTask['scheduled_start'] != null
                        ? _formatTimeString(
                            nextTask['scheduled_start'].toString(),
                          )
                        : 'No time',
                    style: const TextStyle(
                      color: Color(0xFFF5F5F5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _nextTaskMessage(nextTask),
                    style: const TextStyle(
                      color: Color(0xFFB3B3BB),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Verification: $verificationType',
              style: const TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtonForLog(Map<String, dynamic> log) {
    final status = (log['status'] ?? 'pending').toString();
    final verificationType = (log['verification_type'] ?? 'manual').toString();

    if (status == 'done') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0x142E7D32),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2E7D32)),
        ),
        child: const Text(
          'Done',
          style: TextStyle(
            color: Colors.greenAccent,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      );
    }

    if (verificationType == 'manual') {
      final availability = _manualCompletionAvailability(log);

      return ElevatedButton(
        onPressed: (!_isUpdatingLog && availability.canCompleteNow)
            ? () => _markLogDone(log)
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF5F5F5),
          foregroundColor: Colors.black,
          disabledBackgroundColor: const Color(0xFF2A2A2F),
          disabledForegroundColor: const Color(0xFF6F6F76),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          _isUpdatingLog
              ? 'Saving...'
              : availability.canCompleteNow
                  ? 'Mark Done'
                  : 'Locked',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Text(
        verificationType,
        style: const TextStyle(
          color: Color(0xFF9A9AA3),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> log, int index) {
    final status = log['status'].toString();
    final isDone = status == 'done';
    final habit = log['habits'] as Map<String, dynamic>?;
    final goal = habit?['goals'] as Map<String, dynamic>?;
    final availability = _manualCompletionAvailability(log);
    final verificationType = (log['verification_type'] ?? 'manual').toString();
    final state = _taskState(log);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + (index * 70)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF101013),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _taskStateBorderColor(state)),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDone
                        ? Colors.green
                        : state == 'missed'
                            ? const Color(0xFFE57373)
                            : state == 'available'
                                ? const Color(0xFFF5F5F5)
                                : state == 'soon'
                                    ? const Color(0xFFFFD166)
                                    : const Color(0xFF7C7C84),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit?['title']?.toString() ?? 'Untitled Habit',
                        style: const TextStyle(
                          color: Color(0xFFF5F5F5),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        goal?['title']?.toString() ?? 'Unknown Goal',
                        style: const TextStyle(
                          color: Color(0xFF9A9AA3),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${log['scheduled_start'] != null ? _formatTimeString(log['scheduled_start'].toString()) : 'No time'}'
                        '${log['scheduled_end'] != null ? ' – ${_formatTimeString(log['scheduled_end'].toString())}' : ''}',
                        style: const TextStyle(
                          color: Color(0xFFB3B3BB),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildStatusChip(state),
                          Text(
                            'Verification: $verificationType',
                            style: const TextStyle(
                              color: Color(0xFF9A9AA3),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      if (!isDone && verificationType == 'manual') ...[
                        const SizedBox(height: 6),
                        Text(
                          availability.message,
                          style: const TextStyle(
                            color: Color(0xFF7C7C84),
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildActionButtonForLog(log),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskSection({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> logs,
    required String emptyText,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            '$title (${logs.length})',
            subtitle: subtitle,
          ),
          if (logs.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                emptyText,
                style: const TextStyle(color: Color(0xFF9A9AA3)),
              ),
            ),
          ...List.generate(
            logs.length,
            (index) => _buildTaskCard(logs[index], index),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusButton() {
    final hasAvailableNow = _availableLogs.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: hasAvailableNow ? () {} : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF5F5F5),
          foregroundColor: Colors.black,
          disabledBackgroundColor: const Color(0xFF2A2A2F),
          disabledForegroundColor: const Color(0xFF6F6F76),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        icon: const Icon(Icons.center_focus_strong),
        label: Text(
          hasAvailableNow ? 'Focus Mode' : 'No task available now',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFF5F5F5),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFB3B3BB)),
          ),
        ),
      );
    }

    final hasAvailableNow = _availableLogs.isNotEmpty;

    return HoldToRefreshWrapper(
      onRefresh: _loadTodayData,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopHero(),
            if (hasAvailableNow) ...[
              const SizedBox(height: 18),
              _buildTaskSection(
                title: 'Available now',
                subtitle: 'These commitments can be executed right now.',
                logs: _availableLogs,
                emptyText: '',
              ),
            ],
            const SizedBox(height: 18),
            _buildNextTaskCard(),
            const SizedBox(height: 18),
            _buildTaskSection(
              title: 'Missed / expired',
              subtitle: 'These execution windows have already closed.',
              logs: _missedLogs,
              emptyText: 'No missed tasks so far.',
            ),
            const SizedBox(height: 20),
            _buildFocusButton(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0C),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }
}

class _CompletionAvailability {
  final bool canCompleteNow;
  final String message;

  const _CompletionAvailability({
    required this.canCompleteNow,
    required this.message,
  });
}