import 'package:achievr_app/Services/app_clock.dart';
import 'package:achievr_app/Widgets/hold_to_refresh_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _error;

  int _totalToday = 0;
  int _doneToday = 0;
  int _upcomingToday = 0;
  int _availableNowToday = 0;
  int _missedToday = 0;

  int _totalThisWeek = 0;
  int _doneThisWeek = 0;
  int _remainingThisWeek = 0;
  int _missedThisWeek = 0;

  int _totalDoneAllTime = 0;
  int _currentStreak = 0;

  static const Duration _gracePeriod = Duration(minutes: 30);

  DateTime get _screenNow => AppClock.now();

  @override
  void initState() {
    super.initState();
    _loadProgressData();
    AppClock.debugNowNotifier.addListener(_handleClockChange);
  }

  void _handleClockChange() {
    if (!mounted) return;
    _loadProgressData();
  }

  @override
  void dispose() {
    AppClock.debugNowNotifier.removeListener(_handleClockChange);
    super.dispose();
  }

  String _toDateString(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  DateTime? _logStartDateTime(Map<String, dynamic> log) {
    final logDateRaw = log['log_date']?.toString();
    final startRaw = log['scheduled_start']?.toString();

    if (logDateRaw == null || startRaw == null || startRaw.isEmpty) return null;

    final dateParts = logDateRaw.split('-');
    final timeParts = startRaw.split(':');

    if (dateParts.length != 3 || timeParts.length < 2) return null;

    final year = int.tryParse(dateParts[0]) ?? 0;
    final month = int.tryParse(dateParts[1]) ?? 1;
    final day = int.tryParse(dateParts[2]) ?? 1;
    final hour = int.tryParse(timeParts[0]) ?? 0;
    final minute = int.tryParse(timeParts[1]) ?? 0;

    return DateTime(year, month, day, hour, minute);
  }

  DateTime? _logEndDateTime(Map<String, dynamic> log) {
    final logDateRaw = log['log_date']?.toString();
    final endRaw = log['scheduled_end']?.toString();

    if (logDateRaw == null || endRaw == null || endRaw.isEmpty) return null;

    final dateParts = logDateRaw.split('-');
    final timeParts = endRaw.split(':');

    if (dateParts.length != 3 || timeParts.length < 2) return null;

    final year = int.tryParse(dateParts[0]) ?? 0;
    final month = int.tryParse(dateParts[1]) ?? 1;
    final day = int.tryParse(dateParts[2]) ?? 1;
    final hour = int.tryParse(timeParts[0]) ?? 0;
    final minute = int.tryParse(timeParts[1]) ?? 0;

    return DateTime(year, month, day, hour, minute);
  }

  String _classifyLogStatus(Map<String, dynamic> log, DateTime now) {
    final rawStatus = (log['status'] ?? 'pending').toString();

    if (rawStatus == 'done') return 'done';
    if (rawStatus == 'missed' || rawStatus == 'failed') return 'missed';

    final start = _logStartDateTime(log);
    final end = _logEndDateTime(log);

    if (start == null || end == null) return 'remaining';

    final latestAllowed = end.add(_gracePeriod);

    if (now.isBefore(start)) {
      return 'upcoming';
    }

    if (now.isAfter(latestAllowed)) {
      return 'missed';
    }

    return 'available';
  }

  Future<void> _loadProgressData() async {
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

      final now = _screenNow;
      final todayString = _toDateString(now);

      final startOfWeek = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));

      final endOfWeek = startOfWeek.add(const Duration(days: 6));

      final startOfWeekString = _toDateString(startOfWeek);
      final endOfWeekString = _toDateString(endOfWeek);

      final todayLogsResponse = await supabase
          .from('habit_logs')
          .select('status, log_date, scheduled_start, scheduled_end')
          .eq('user_id', user.id)
          .eq('log_date', todayString);

      final todayLogs = List<Map<String, dynamic>>.from(todayLogsResponse);

      final weeklyLogsResponse = await supabase
          .from('habit_logs')
          .select('status, log_date, scheduled_start, scheduled_end')
          .eq('user_id', user.id)
          .gte('log_date', startOfWeekString)
          .lte('log_date', endOfWeekString)
          .order('log_date', ascending: false);

      final weeklyLogs = List<Map<String, dynamic>>.from(weeklyLogsResponse);

      final allDoneResponse = await supabase
          .from('habit_logs')
          .select('log_id')
          .eq('user_id', user.id)
          .eq('status', 'done');

      final allDoneLogs = List<Map<String, dynamic>>.from(allDoneResponse);

      final allLogsForStreakResponse = await supabase
          .from('habit_logs')
          .select('status, log_date')
          .eq('user_id', user.id)
          .lte('log_date', todayString)
          .order('log_date', ascending: false);

      final allLogsForStreak =
          List<Map<String, dynamic>>.from(allLogsForStreakResponse);

      final totalToday = todayLogs.length;

      final doneToday =
          todayLogs.where((log) => _classifyLogStatus(log, now) == 'done').length;

      final upcomingToday =
          todayLogs.where((log) => _classifyLogStatus(log, now) == 'upcoming').length;

      final availableNowToday =
          todayLogs.where((log) => _classifyLogStatus(log, now) == 'available').length;

      final missedToday =
          todayLogs.where((log) => _classifyLogStatus(log, now) == 'missed').length;

      final totalThisWeek = weeklyLogs.length;

      final doneThisWeek =
          weeklyLogs.where((log) => _classifyLogStatus(log, now) == 'done').length;

      final missedThisWeek =
          weeklyLogs.where((log) => _classifyLogStatus(log, now) == 'missed').length;

      final remainingThisWeek = weeklyLogs.where((log) {
        final status = _classifyLogStatus(log, now);
        return status == 'upcoming' ||
            status == 'available' ||
            status == 'remaining';
      }).length;

      final streak = _calculateCurrentStreak(allLogsForStreak, todayString);

      if (!mounted) return;

      setState(() {
        _totalToday = totalToday;
        _doneToday = doneToday;
        _upcomingToday = upcomingToday;
        _availableNowToday = availableNowToday;
        _missedToday = missedToday;

        _totalThisWeek = totalThisWeek;
        _doneThisWeek = doneThisWeek;
        _remainingThisWeek = remainingThisWeek;
        _missedThisWeek = missedThisWeek;

        _totalDoneAllTime = allDoneLogs.length;
        _currentStreak = streak;
        _isLoading = false;
      });
    } catch (e, st) {
      debugPrint('PROGRESS SCREEN ERROR: $e');
      debugPrint('$st');

      if (!mounted) return;

      setState(() {
        _error = 'Failed to load progress.\n$e';
        _isLoading = false;
      });
    }
  }

  int _calculateCurrentStreak(
    List<Map<String, dynamic>> logs,
    String todayString,
  ) {
    if (logs.isEmpty) return 0;

    final Map<String, List<Map<String, dynamic>>> groupedByDate = {};

    for (final log in logs) {
      final date = log['log_date']?.toString();
      if (date == null) continue;
      groupedByDate.putIfAbsent(date, () => []).add(log);
    }

    int streak = 0;
    var cursor = AppClock.today();

    while (true) {
      final dateString = _toDateString(cursor);

      if (dateString.compareTo(todayString) > 0) {
        cursor = cursor.subtract(const Duration(days: 1));
        continue;
      }

      final dayLogs = groupedByDate[dateString];

      if (dayLogs == null || dayLogs.isEmpty) {
        break;
      }

      final hasDone =
          dayLogs.any((log) => log['status'].toString() == 'done');

      final hasMissed = dayLogs.any((log) {
        final status = log['status'].toString();
        return status == 'missed' || status == 'failed';
      });

      if (hasDone && !hasMissed) {
        streak++;
      } else if (hasDone) {
        streak++;
      } else {
        break;
      }

      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  double get _todayCompletionRate {
    if (_totalToday == 0) return 0;
    return _doneToday / _totalToday;
  }

  double get _weekCompletionRate {
    if (_totalThisWeek == 0) return 0;
    return _doneThisWeek / _totalThisWeek;
  }

  double get _todayRecoverabilityRate {
    if (_totalToday == 0) return 0;
    return (_doneToday + _availableNowToday + _upcomingToday) / _totalToday;
  }

  double get _weekRecoverabilityRate {
    if (_totalThisWeek == 0) return 0;
    return (_doneThisWeek + _remainingThisWeek) / _totalThisWeek;
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
            style: const TextStyle(
              color: Color(0xFF9A9AA3),
              fontSize: 12,
            ),
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

  Widget _buildTopCard() {
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
            'Progress',
            style: TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Track consistency, recoverability, and the discipline you are building over time.',
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
                  label: 'Current Streak',
                  value: '$_currentStreak',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'All-Time Done',
                  value: '$_totalDoneAllTime',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar({
    required String title,
    required String subtitle,
    required double value,
    required String trailingText,
  }) {
    return Container(
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
          _buildSectionTitle(title, subtitle: subtitle),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: value.clamp(0, 1),
                    minHeight: 10,
                    backgroundColor: const Color(0xFF101013),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFF5F5F5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                trailingText,
                style: const TextStyle(
                  color: Color(0xFFF5F5F5),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayStatusCard() {
    String headline;
    String body;

    if (_totalToday == 0) {
      headline = 'No commitments today';
      body = 'There are no scheduled tasks to execute today.';
    } else if (_availableNowToday > 0) {
      headline = 'Today is recoverable now';
      body =
          'You currently have $_availableNowToday task${_availableNowToday == 1 ? '' : 's'} available to execute right now.';
    } else if (_doneToday > 0 && _upcomingToday > 0) {
      headline = 'Momentum is active';
      body =
          'You have already completed $_doneToday task${_doneToday == 1 ? '' : 's'}, and $_upcomingToday more ${_upcomingToday == 1 ? 'is' : 'are'} still coming later.';
    } else if (_upcomingToday > 0) {
      headline = 'Later commitments remain';
      body =
          'Nothing is open right now, but $_upcomingToday task${_upcomingToday == 1 ? '' : 's'} ${_upcomingToday == 1 ? 'is' : 'are'} still scheduled for later today.';
    } else if (_missedToday > 0) {
      headline = 'Today has execution loss';
      body =
          '$_missedToday task${_missedToday == 1 ? '' : 's'} ${_missedToday == 1 ? 'has' : 'have'} already missed its completion window.';
    } else {
      headline = 'Today is stable';
      body = 'Your current day is under control.';
    }

    return Container(
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
            'Day status',
            subtitle: 'What the current day still allows.',
          ),
          Text(
            headline,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFFB3B3BB),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekStatusCard() {
    String headline;
    String body;

    if (_totalThisWeek == 0) {
      headline = 'No weekly commitments';
      body = 'There are no scheduled tasks recorded for this week.';
    } else if (_remainingThisWeek > 0) {
      headline = 'The week is still recoverable';
      body =
          'You have completed $_doneThisWeek of $_totalThisWeek weekly commitments, and $_remainingThisWeek ${_remainingThisWeek == 1 ? 'still remains' : 'still remain'} recoverable.';
    } else if (_missedThisWeek > 0) {
      headline = 'This week has unrecovered losses';
      body =
          '$_missedThisWeek task${_missedThisWeek == 1 ? '' : 's'} ${_missedThisWeek == 1 ? 'was' : 'were'} missed this week, with no remaining weekly commitments left to offset them.';
    } else {
      headline = 'The week is under control';
      body = 'Your weekly commitments are being handled cleanly so far.';
    }

    return Container(
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
            'Week status',
            subtitle: 'How much of the current week is still recoverable.',
          ),
          Text(
            headline,
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFFB3B3BB),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryGrid() {
    return Container(
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
            'Summary',
            subtitle: 'A clearer breakdown of what is done and what is still ahead.',
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _buildMetricChip(
                  label: 'Done Today',
                  value: '$_doneToday',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Coming Later',
                  value: '$_upcomingToday',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMetricChip(
                  label: 'Available Now',
                  value: '$_availableNowToday',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Missed Today',
                  value: '$_missedToday',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMetricChip(
                  label: 'Done This Week',
                  value: '$_doneThisWeek',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Recoverable Week',
                  value: '$_remainingThisWeek',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMetricChip(
                  label: 'Missed This Week',
                  value: '$_missedThisWeek',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricChip(
                  label: 'Total Today',
                  value: '$_totalToday',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard() {
    String message;

    if (_currentStreak >= 7 && _availableNowToday > 0) {
      message =
          'You are building real momentum. Protect the streak by executing the next available commitment now.';
    } else if (_availableNowToday > 0) {
      message =
          'You have habits available right now. Executing one will immediately improve today’s recovery picture.';
    } else if (_doneToday > 0 && _upcomingToday > 0) {
      message =
          'You already made progress today, and more commitments are still scheduled ahead. Protect the rhythm.';
    } else if (_upcomingToday > 0) {
      message =
          'More work is still coming later today. Stay ready for the next execution window.';
    } else if (_missedToday > 0 && _remainingThisWeek > 0) {
      message =
          'Some of today has already slipped, but the week is still recoverable. Use the remaining commitments well.';
    } else if (_doneToday > 0) {
      message =
          'Today already has momentum. Finish strong and protect consistency.';
    } else {
      message = 'No active tasks recorded for today yet.';
    }

    return Container(
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
            'Discipline insight',
            subtitle: 'A quick read on your current trajectory.',
          ),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFFB3B3BB),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
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
            style: const TextStyle(
              color: Color(0xFFB3B3BB),
            ),
          ),
        ),
      );
    }

    return HoldToRefreshWrapper(
      onRefresh: _loadProgressData,
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
            _buildSummaryGrid(),
            _buildDayStatusCard(),
            _buildProgressBar(
              title: 'Today completion',
              subtitle: 'Completed out of everything scheduled for today.',
              value: _todayCompletionRate,
              trailingText: '${(_todayCompletionRate * 100).round()}%',
            ),
            _buildProgressBar(
              title: 'Today recoverability',
              subtitle: 'Done plus still-recoverable work out of today’s total.',
              value: _todayRecoverabilityRate,
              trailingText: '${(_todayRecoverabilityRate * 100).round()}%',
            ),
            _buildWeekStatusCard(),
            _buildProgressBar(
              title: 'Weekly completion',
              subtitle: 'Completed out of everything scheduled for this week.',
              value: _weekCompletionRate,
              trailingText: '${(_weekCompletionRate * 100).round()}%',
            ),
            _buildProgressBar(
              title: 'Weekly recoverability',
              subtitle: 'Done plus remaining recoverable work for this week.',
              value: _weekRecoverabilityRate,
              trailingText: '${(_weekRecoverabilityRate * 100).round()}%',
            ),
            _buildInsightCard(),
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