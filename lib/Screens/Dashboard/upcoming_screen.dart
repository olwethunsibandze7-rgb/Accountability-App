// ignore_for_file: unused_element

import 'package:achievr_app/Services/app_clock.dart';
import 'package:achievr_app/Widgets/hold_to_refresh_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UpcomingScreen extends StatefulWidget {
  const UpcomingScreen({super.key});

  @override
  State<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends State<UpcomingScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _error;

  List<Map<String, dynamic>> _weeklySchedules = [];
  Set<String> _closedOccurrenceKeys = <String>{};

  static const Map<int, String> _dayNames = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  static const Set<String> _closedLogStatuses = {
    'done',
    'submitted',
    'pending_verification',
    'failed',
    'missed',
    'rejected',
  };

  DateTime get _screenNow => AppClock.now();

  @override
  void initState() {
    super.initState();
    _loadUpcomingData();
    AppClock.debugNowNotifier.addListener(_handleClockChange);
  }

  void _handleClockChange() {
    if (!mounted) return;
    _loadUpcomingData();
  }

  @override
  void dispose() {
    AppClock.debugNowNotifier.removeListener(_handleClockChange);
    super.dispose();
  }

  Future<void> _loadUpcomingData() async {
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

      final goalsResponse = await supabase
          .from('goals')
          .select('goal_id, title, active')
          .eq('user_id', user.id)
          .eq('active', true)
          .order('created_at', ascending: true);

      final List<Map<String, dynamic>> fetchedGoals =
          List<Map<String, dynamic>>.from(goalsResponse);

      if (fetchedGoals.isEmpty) {
        if (!mounted) return;
        setState(() {
          _weeklySchedules = [];
          _closedOccurrenceKeys = <String>{};
          _isLoading = false;
        });
        return;
      }

      final goalIds =
          fetchedGoals.map((goal) => goal['goal_id'].toString()).toList();

      final habitsResponse = await supabase
          .from('habits')
          .select('habit_id, goal_id, title, verification_type, active')
          .inFilter('goal_id', goalIds)
          .eq('active', true)
          .order('created_at', ascending: true);

      final List<Map<String, dynamic>> fetchedHabits =
          List<Map<String, dynamic>>.from(habitsResponse);

      if (fetchedHabits.isEmpty) {
        if (!mounted) return;
        setState(() {
          _weeklySchedules = [];
          _closedOccurrenceKeys = <String>{};
          _isLoading = false;
        });
        return;
      }

      final habitIds =
          fetchedHabits.map((habit) => habit['habit_id'].toString()).toList();

      final schedulesResponse = await supabase
          .from('habit_schedules')
          .select(
            'schedule_id, habit_id, day_of_week, start_time, end_time, source',
          )
          .inFilter('habit_id', habitIds)
          .order('day_of_week', ascending: true)
          .order('start_time', ascending: true);

      final List<Map<String, dynamic>> fetchedSchedules =
          List<Map<String, dynamic>>.from(schedulesResponse);

      final now = _screenNow;
      final tomorrow = now.add(const Duration(days: 1));

      final logsResponse = await supabase
          .from('habit_logs')
          .select(
            'log_id, habit_id, schedule_id, log_date, scheduled_start, scheduled_end, status',
          )
          .eq('user_id', user.id)
          .gte('log_date', _formatDateKey(now))
          .lte('log_date', _formatDateKey(tomorrow));

      final List<Map<String, dynamic>> fetchedLogs =
          List<Map<String, dynamic>>.from(logsResponse);

      final goalById = {
        for (final goal in fetchedGoals) goal['goal_id'].toString(): goal,
      };

      final habitById = {
        for (final habit in fetchedHabits) habit['habit_id'].toString(): habit,
      };

      final transformedSchedules = fetchedSchedules.map((schedule) {
        final habit = habitById[schedule['habit_id'].toString()];
        final goal =
            habit != null ? goalById[habit['goal_id'].toString()] : null;

        return {
          'schedule_id': schedule['schedule_id'],
          'habit_id': schedule['habit_id'],
          'day_of_week': schedule['day_of_week'],
          'start_time': schedule['start_time'],
          'end_time': schedule['end_time'],
          'source': schedule['source'],
          'habit_title': habit?['title'] ?? 'Untitled Habit',
          'goal_title': goal?['title'] ?? 'Unknown Goal',
          'verification_type': habit?['verification_type'] ?? 'manual',
        };
      }).toList();

      final closedKeys = <String>{};
      for (final log in fetchedLogs) {
        final status = (log['status'] ?? '').toString().trim().toLowerCase();
        if (!_closedLogStatuses.contains(status)) continue;

        final scheduleId = log['schedule_id']?.toString();
        final habitId = log['habit_id']?.toString();
        final logDate = log['log_date']?.toString();
        final start = log['scheduled_start']?.toString();

        if (logDate == null || start == null) continue;

        if (scheduleId != null && scheduleId.isNotEmpty) {
          closedKeys.add('schedule:$scheduleId|date:$logDate|start:$start');
        }

        if (habitId != null && habitId.isNotEmpty) {
          closedKeys.add('habit:$habitId|date:$logDate|start:$start');
        }
      }

      if (!mounted) return;

      setState(() {
        _weeklySchedules = List<Map<String, dynamic>>.from(transformedSchedules);
        _closedOccurrenceKeys = closedKeys;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('UPCOMING SCREEN ERROR: $e');
      debugPrint('$st');

      if (!mounted) return;

      setState(() {
        _error = 'Failed to load upcoming schedule.\n$e';
        _isLoading = false;
      });
    }
  }

  String _formatDateKey(DateTime dt) {
    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  int _timeToMinutes(String? hhmmss) {
    if (hhmmss == null || hhmmss.isEmpty) return 0;

    final parts = hhmmss.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    return (hour * 60) + minute;
  }

  int _durationMinutes(Map<String, dynamic> item) {
    final start = _timeToMinutes(item['start_time']?.toString());
    final end = _timeToMinutes(item['end_time']?.toString());

    if (end <= start) return 0;
    return end - start;
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

  String _formatDurationLabel(int totalMinutes) {
    if (totalMinutes <= 0) return '0m';

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}m';
    }
    if (hours > 0) {
      return '${hours}h';
    }
    return '${minutes}m';
  }

  String _dayLoadLabel(int totalMinutes, int taskCount) {
    if (taskCount == 0) return 'Free';
    if (taskCount <= 2 && totalMinutes <= 90) return 'Light';
    if (taskCount <= 4 && totalMinutes <= 240) return 'Moderate';
    return 'Heavy';
  }

  Color _dayLoadColor(String load) {
    switch (load) {
      case 'Free':
        return const Color(0xFF7C7C84);
      case 'Light':
        return const Color(0xFFB3E5FC);
      case 'Moderate':
        return const Color(0xFFFFD166);
      case 'Heavy':
        return const Color(0xFFFF8A80);
      default:
        return const Color(0xFF7C7C84);
    }
  }

  String _verificationLabel(String raw) {
    switch (raw) {
      case 'manual':
        return 'Manual';
      case 'focus_auto':
        return 'Focus Auto';
      case 'partner':
        return 'Partner Review';
      case 'focus_partner':
        return 'Focus + Partner';
      case 'location':
        return 'Location';
      case 'location_focus':
        return 'Location + Focus';
      case 'location_partner':
        return 'Location + Partner';
      case 'location_focus_partner':
        return 'Location + Focus + Partner';
      default:
        return raw.replaceAll('_', ' ');
    }
  }

  Map<int, List<Map<String, dynamic>>> get _groupedSchedules {
    final Map<int, List<Map<String, dynamic>>> grouped = {
      1: [],
      2: [],
      3: [],
      4: [],
      5: [],
      6: [],
      7: [],
    };

    for (final item in _weeklySchedules) {
      final day = item['day_of_week'] as int?;
      if (day != null && grouped.containsKey(day)) {
        grouped[day]!.add(item);
      }
    }

    for (final key in grouped.keys) {
      grouped[key]!.sort((a, b) {
        final aStart = _timeToMinutes(a['start_time']?.toString());
        final bStart = _timeToMinutes(b['start_time']?.toString());
        return aStart.compareTo(bStart);
      });
    }

    return grouped;
  }

  List<int> get _orderedDays {
    final today = _screenNow.weekday;
    final List<int> days = [1, 2, 3, 4, 5, 6, 7];

    days.sort((a, b) {
      final aDistance = (a - today) % 7;
      final bDistance = (b - today) % 7;
      return aDistance.compareTo(bDistance);
    });

    return days;
  }

  List<int> get _orderedDaysWithTasks {
    final grouped = _groupedSchedules;
    return _orderedDays.where((day) => (grouped[day] ?? []).isNotEmpty).toList();
  }

  String _daySubtitle(int day) {
    final today = _screenNow.weekday;
    if (day == today) return 'Today';
    if (day == ((today % 7) + 1)) return 'Tomorrow';
    return 'Upcoming';
  }

  int _dayTotalMinutes(List<Map<String, dynamic>> items) {
    return items.fold<int>(0, (sum, item) => sum + _durationMinutes(item));
  }

  DateTime _nextOccurrenceDate(int targetWeekday) {
    final now = _screenNow;
    final startOfToday = DateTime(now.year, now.month, now.day);
    final distance = (targetWeekday - now.weekday) % 7;
    return startOfToday.add(Duration(days: distance));
  }

  DateTime? _occurrenceStartDateTime(Map<String, dynamic> item) {
    final day = item['day_of_week'] as int?;
    final rawStart = item['start_time']?.toString();

    if (day == null || rawStart == null || rawStart.isEmpty) return null;

    final date = _nextOccurrenceDate(day);
    final parts = rawStart.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final second = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;

    return DateTime(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
      second,
    );
  }

  String _occurrenceKeyFor(Map<String, dynamic> item, DateTime occurrenceDate) {
    final scheduleId = item['schedule_id']?.toString();
    final habitId = item['habit_id']?.toString();
    final start = item['start_time']?.toString() ?? '';
    final dateKey = _formatDateKey(occurrenceDate);

    if (scheduleId != null && scheduleId.isNotEmpty) {
      return 'schedule:$scheduleId|date:$dateKey|start:$start';
    }

    return 'habit:$habitId|date:$dateKey|start:$start';
  }

  bool _isOccurrenceClosed(Map<String, dynamic> item, DateTime occurrenceDate) {
    final scheduleKey = _occurrenceKeyFor(item, occurrenceDate);
    if (_closedOccurrenceKeys.contains(scheduleKey)) {
      return true;
    }

    final habitId = item['habit_id']?.toString();
    final start = item['start_time']?.toString() ?? '';
    final dateKey = _formatDateKey(occurrenceDate);
    final fallbackKey = 'habit:$habitId|date:$dateKey|start:$start';

    return _closedOccurrenceKeys.contains(fallbackKey);
  }

  List<Map<String, dynamic>> get _next24HoursItems {
    final now = _screenNow;
    final horizon = now.add(const Duration(hours: 24));

    final List<Map<String, dynamic>> upcoming = [];

    for (final item in _weeklySchedules) {
      final startAt = _occurrenceStartDateTime(item);
      if (startAt == null) continue;
      if (startAt.isBefore(now)) continue;
      if (startAt.isAfter(horizon)) continue;
      if (_isOccurrenceClosed(item, startAt)) continue;

      upcoming.add({
        ...item,
        '_occurrence_start': startAt,
      });
    }

    upcoming.sort((a, b) {
      final aStart = a['_occurrence_start'] as DateTime;
      final bStart = b['_occurrence_start'] as DateTime;
      return aStart.compareTo(bStart);
    });

    return upcoming.take(3).toList();
  }

  int get _openNext24HoursCount => _next24HoursItems.length;

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

  Widget _buildTopCard() {
    final activeDays = _groupedSchedules.entries
        .where((e) => e.value.isNotEmpty)
        .length;

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
          const Text(
            'Upcoming',
            style: TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'See the next open commitments in your system and your weekly rhythm at a glance.',
            style: TextStyle(
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
                  label: 'Weekly Slots',
                  value: '${_weeklySchedules.length}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Active Days',
                  value: '$activeDays',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Open Next 24h',
                  value: '$_openNext24HoursCount',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadChip(String load) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _dayLoadColor(load)),
      ),
      child: Text(
        load,
        style: TextStyle(
          color: _dayLoadColor(load),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildNext24HoursCard() {
    final items = _next24HoursItems;

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
            'Next 24 hours',
            subtitle: 'Only open upcoming instances. Finished items are hidden.',
          ),
          if (items.isEmpty)
            const Text(
              'Nothing open is coming up in the next 24 hours.',
              style: TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 13,
              ),
            ),
          ...items.map((item) {
            final startAt = item['_occurrence_start'] as DateTime;
            return Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF101013),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF232329)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFF5F5F5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['habit_title'].toString(),
                          style: const TextStyle(
                            color: Color(0xFFF5F5F5),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item['goal_title'].toString(),
                          style: const TextStyle(
                            color: Color(0xFF9A9AA3),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_dayNames[startAt.weekday] ?? 'Unknown Day'} • ${_formatTimeString(item['start_time'].toString())} – ${_formatTimeString(item['end_time'].toString())}',
                          style: const TextStyle(
                            color: Color(0xFFB3B3BB),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEmptyWeekCard() {
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
            'Weekly view',
            subtitle: 'Your recurring schedule will appear here.',
          ),
          const Text(
            'No scheduled habits found for this week.',
            style: TextStyle(
              color: Color(0xFF9A9AA3),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(int day, List<Map<String, dynamic>> items, int index) {
    final totalMinutes = _dayTotalMinutes(items);
    final load = _dayLoadLabel(totalMinutes, items.length);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + (index * 70)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(top: 14),
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
              _dayNames[day] ?? 'Unknown Day',
              subtitle: _daySubtitle(day),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${items.length} task${items.length == 1 ? '' : 's'} • ${_formatDurationLabel(totalMinutes)}',
                    style: const TextStyle(
                      color: Color(0xFFB3B3BB),
                      fontSize: 12,
                    ),
                  ),
                ),
                _buildLoadChip(load),
              ],
            ),
            ...items.map((item) {
              return Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF101013),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF232329)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF7C7C84),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['habit_title'].toString(),
                            style: const TextStyle(
                              color: Color(0xFFF5F5F5),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item['goal_title'].toString(),
                            style: const TextStyle(
                              color: Color(0xFF9A9AA3),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_formatTimeString(item['start_time'].toString())} – ${_formatTimeString(item['end_time'].toString())}',
                            style: const TextStyle(
                              color: Color(0xFFB3B3BB),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
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

    final grouped = _groupedSchedules;
    final orderedDaysWithTasks = _orderedDaysWithTasks;

    return HoldToRefreshWrapper(
      onRefresh: _loadUpcomingData,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopCard(),
            const SizedBox(height: 18),
            _buildNext24HoursCard(),
            const SizedBox(height: 18),
            if (orderedDaysWithTasks.isEmpty)
              _buildEmptyWeekCard()
            else
              ...List.generate(
                orderedDaysWithTasks.length,
                (index) => _buildDayCard(
                  orderedDaysWithTasks[index],
                  grouped[orderedDaysWithTasks[index]] ?? [],
                  index,
                ),
              ),
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