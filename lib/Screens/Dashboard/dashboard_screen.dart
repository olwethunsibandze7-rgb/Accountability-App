import 'package:flutter/material.dart';
import 'package:achievr_app/Services/app_clock.dart';
import 'package:achievr_app/Screens/Dashboard/today_screen.dart';
import 'package:achievr_app/Screens/Dashboard/upcoming_screen.dart';
import 'package:achievr_app/Screens/Dashboard/bright_screen.dart';
import 'package:achievr_app/Screens/Dashboard/progress_screen.dart';
import 'package:achievr_app/Screens/Dashboard/social_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  int _screenVersion = 0;

  List<Widget> get _pages => [
        TodayScreen(key: ValueKey('today_$_screenVersion')),
        UpcomingScreen(key: ValueKey('upcoming_$_screenVersion')),
        BrightScreen(key: ValueKey('bright_$_screenVersion')),
        ProgressScreen(key: ValueKey('progress_$_screenVersion')),
        SocialScreen(key: ValueKey('social_$_screenVersion')),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      _refreshAllTabs();
    }
  }

  void _refreshAllTabs() {
    if (!mounted) return;

    setState(() {
      _screenVersion++;
    });
  }

  void _handleTabTap(int index) {
    if (!mounted) return;

    if (_currentIndex == index) {
      _refreshAllTabs();
      return;
    }

    setState(() {
      _currentIndex = index;
    });
  }

  Future<void> _openDebugClockSheet() async {
    DateTime selected = AppClock.debugNow ?? AppClock.now();

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF17171A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickDate() async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selected,
                firstDate: DateTime(2024),
                lastDate: DateTime(2030),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: Color(0xFFF5F5F5),
                        onPrimary: Colors.black,
                        surface: Color(0xFF17171A),
                        onSurface: Color(0xFFF5F5F5),
                      ),
                      dialogTheme: const DialogThemeData(
                        backgroundColor: Color(0xFF17171A),
                      ),
                    ),
                    child: child!,
                  );
                },
              );

              if (picked != null) {
                setModalState(() {
                  selected = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    selected.hour,
                    selected.minute,
                  );
                });
              }
            }

            Future<void> pickTime() async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: selected.hour,
                  minute: selected.minute,
                ),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: Color(0xFFF5F5F5),
                        onPrimary: Colors.black,
                        surface: Color(0xFF17171A),
                        onSurface: Color(0xFFF5F5F5),
                      ),
                      timePickerTheme: const TimePickerThemeData(
                        backgroundColor: Color(0xFF17171A),
                      ),
                    ),
                    child: child!,
                  );
                },
              );

              if (picked != null) {
                setModalState(() {
                  selected = DateTime(
                    selected.year,
                    selected.month,
                    selected.day,
                    picked.hour,
                    picked.minute,
                  );
                });
              }
            }

            final formattedDate =
                '${selected.year.toString().padLeft(4, '0')}-'
                '${selected.month.toString().padLeft(2, '0')}-'
                '${selected.day.toString().padLeft(2, '0')}';

            final formattedTime =
                '${selected.hour.toString().padLeft(2, '0')}:'
                '${selected.minute.toString().padLeft(2, '0')}';

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Debug Clock',
                    style: TextStyle(
                      color: Color(0xFFF5F5F5),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Set a virtual app time for testing schedules, verification windows, and upcoming ordering.',
                    style: TextStyle(
                      color: Color(0xFFB3B3BB),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101013),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF232329)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current app time',
                          style: TextStyle(
                            color: Color(0xFF9A9AA3),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          AppClock.isDebugClockEnabled
                              ? AppClock.debugLabel()
                              : 'Real device time',
                          style: const TextStyle(
                            color: Color(0xFFF5F5F5),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: pickDate,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF5F5F5),
                            side: const BorderSide(color: Color(0xFF232329)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(formattedDate),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: pickTime,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF5F5F5),
                            side: const BorderSide(color: Color(0xFF232329)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(formattedTime),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        AppClock.setDebugTime(selected);
                        Navigator.pop(context);
                        _refreshAllTabs();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Debug time set to ${AppClock.debugLabel()}',
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF5F5F5),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Apply Debug Time',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        AppClock.clearDebugTime();
                        Navigator.pop(context);
                        _refreshAllTabs();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Returned to real device time.'),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB3B3BB),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Use Real Time'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  FloatingActionButton _buildClockFab() {
    return FloatingActionButton.extended(
      onPressed: _openDebugClockSheet,
      backgroundColor: const Color(0xFF17171A),
      foregroundColor: const Color(0xFFF5F5F5),
      elevation: 0,
      label: Text(
        AppClock.isDebugClockEnabled ? 'Debug Time' : 'Clock',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      icon: const Icon(Icons.schedule),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0C),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      floatingActionButton: _buildClockFab(),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Color(0xFF1E1E22),
              width: 0.8,
            ),
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashFactory: NoSplash.splashFactory,
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _handleTabTap,
            type: BottomNavigationBarType.fixed,
            backgroundColor: const Color(0xFF121214),
            elevation: 0,
            enableFeedback: false,
            selectedItemColor: const Color(0xFFF5F5F5),
            unselectedItemColor: const Color(0xFF6F6F76),
            selectedFontSize: 11,
            unselectedFontSize: 11,
            selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
            ),
            selectedIconTheme: const IconThemeData(size: 22, opacity: 1),
            unselectedIconTheme: const IconThemeData(size: 22, opacity: 1),
            showUnselectedLabels: true,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.today_outlined),
                activeIcon: Icon(Icons.today),
                label: 'Today',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.calendar_month_outlined),
                activeIcon: Icon(Icons.calendar_month),
                label: 'Upcoming',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.auto_awesome_outlined),
                activeIcon: Icon(Icons.auto_awesome),
                label: 'Bright',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.bar_chart_outlined),
                activeIcon: Icon(Icons.bar_chart),
                label: 'Progress',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.groups_outlined),
                activeIcon: Icon(Icons.groups),
                label: 'Social',
              ),
            ],
          ),
        ),
      ),
    );
  }
}