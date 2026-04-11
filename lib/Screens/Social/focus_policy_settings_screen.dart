import 'package:achievr_app/Services/app_policy_service.dart';
import 'package:achievr_app/Services/installed_apps_service.dart';
import 'package:flutter/material.dart';

class FocusPolicySettingsScreen extends StatefulWidget {
  final String habitId;
  final String habitTitle;
  final String verificationType;

  const FocusPolicySettingsScreen({
    super.key,
    required this.habitId,
    required this.habitTitle,
    required this.verificationType,
  });

  @override
  State<FocusPolicySettingsScreen> createState() =>
      _FocusPolicySettingsScreenState();
}

class _FocusPolicySettingsScreenState
    extends State<FocusPolicySettingsScreen> {
  final AppPolicyService _appPolicyService = AppPolicyService();
  final InstalledAppsService _installedAppsService = InstalledAppsService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isReplacingApps = false;
  bool _isLoadingInstalledApps = false;
  String? _error;

  String _policyMode = 'achievr_only';
  int _leaveGraceSeconds = 30;
  bool _allowScreenOff = true;

  List<Map<String, dynamic>> _allowedApps = [];

  bool get _supportsFocusPolicy {
    return widget.verificationType == 'focus_auto' ||
        widget.verificationType == 'focus_partner' ||
        widget.verificationType == 'location_focus' ||
        widget.verificationType == 'location_focus_partner';
  }

  @override
  void initState() {
    super.initState();
    _loadPolicy();
  }

  Future<void> _loadPolicy() async {
    if (!_supportsFocusPolicy) {
      setState(() {
        _isLoading = false;
        _error =
            'Focus policy settings only apply to focus-based verification habits.';
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final fullPolicy = await _appPolicyService.fetchFullAppPolicyForHabit(
        habitId: widget.habitId,
      );

      final policy = fullPolicy['policy'] as Map<String, dynamic>?;
      final allowedApps =
          List<Map<String, dynamic>>.from(fullPolicy['allowed_apps'] ?? []);

      final policyMode =
          (policy?['policy_mode'] ?? 'achievr_only').toString().trim();
      final graceSeconds = _coerceInt(policy?['leave_grace_seconds']) ?? 30;

      if (!mounted) return;

      setState(() {
        _policyMode = policyMode == 'allow_list' ? 'allow_list' : 'achievr_only';
        _leaveGraceSeconds = graceSeconds;
        _allowScreenOff = true;
        _allowedApps = allowedApps;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Failed to load focus policy.\n$e';
        _isLoading = false;
      });
    }
  }

  int? _coerceInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString());
  }

  int get _derivedGraceMinutes => (_leaveGraceSeconds / 60).round();

  Future<void> _savePolicy() async {
    if (!_supportsFocusPolicy) return;

    try {
      setState(() {
        _isSaving = true;
        _error = null;
      });

      await _appPolicyService.upsertHabitAppPolicy(
        habitId: widget.habitId,
        policyMode: _policyMode,
        leaveGraceSeconds: _leaveGraceSeconds,
        allowScreenOff: _allowScreenOff,
      );

      if (_policyMode == 'achievr_only' && _allowedApps.isNotEmpty) {
        await _appPolicyService.replaceAllowedAppsForHabit(
          habitId: widget.habitId,
          apps: const [],
        );
      }

      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Focus policy saved.')),
      );

      await _loadPolicy();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _error = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save focus policy: $e')),
      );
    }
  }

Future<void> _addAllowedApp() async {
  if (_policyMode != 'allow_list') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Switch to allow-list mode before adding apps.'),
      ),
    );
    return;
  }

  if (_allowedApps.length >= 2) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You can only allow up to 2 apps for a focus habit.'),
      ),
    );
    return;
  }

  try {
    setState(() {
      _isLoadingInstalledApps = true;
      _error = null;
    });

    // Make sure the backend policy row is already saved as allow_list
    await _appPolicyService.upsertHabitAppPolicy(
      habitId: widget.habitId,
      policyMode: 'allow_list',
      leaveGraceSeconds: _leaveGraceSeconds,
      allowScreenOff: _allowScreenOff,
    );

    final installedApps = await _installedAppsService.getLaunchableApps();

    if (!mounted) return;

    setState(() {
      _isLoadingInstalledApps = false;
    });

    if (installedApps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No installed apps were found.'),
        ),
      );
      return;
    }

    final alreadyAddedPackages = _allowedApps
        .map((app) => (app['app_identifier'] ?? '').toString())
        .toSet();

    final filteredApps = installedApps
        .where(
          (app) => !alreadyAddedPackages.contains(app['package_name'] ?? ''),
        )
        .toList();

    if (filteredApps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All available apps are already in the allow list.'),
        ),
      );
      return;
    }

    final selected = await _showInstalledAppPicker(filteredApps);
    if (selected == null) return;

    final label = (selected['app_label'] ?? '').trim();
    final identifier = (selected['package_name'] ?? '').trim();

    if (label.isEmpty || identifier.isEmpty) return;

    setState(() {
      _isReplacingApps = true;
    });

    await _appPolicyService.addAllowedAppToHabit(
      habitId: widget.habitId,
      appIdentifier: identifier,
      appLabel: label,
    );

    await _loadPolicy();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label added to allowed apps.')),
    );
  } catch (e) {
    if (!mounted) return;

    setState(() {
      _isLoadingInstalledApps = false;
      _isReplacingApps = false;
      _error = e.toString();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to load installed apps: $e')),
    );
  } finally {
    if (mounted) {
      setState(() {
        _isLoadingInstalledApps = false;
        _isReplacingApps = false;
      });
    }
  }
}

  Future<Map<String, String>?> _showInstalledAppPicker(
    List<Map<String, String>> apps,
  ) async {
    final searchController = TextEditingController();
    List<Map<String, String>> filtered = List<Map<String, String>>.from(apps);

    final selected = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF17171A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void applyFilter(String query) {
              final q = query.trim().toLowerCase();

              setModalState(() {
                filtered = apps.where((app) {
                  final label = (app['app_label'] ?? '').toLowerCase();
                  final pkg = (app['package_name'] ?? '').toLowerCase();
                  return label.contains(q) || pkg.contains(q);
                }).toList();
              });
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.75,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Choose allowed app',
                        style: TextStyle(
                          color: Color(0xFFF5F5F5),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Select up to 2 apps the user is allowed to use during this focus session.',
                        style: TextStyle(
                          color: Color(0xFFB3B3BB),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: searchController,
                        onChanged: applyFilter,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          prefixIcon:
                              const Icon(Icons.search, color: Colors.white70),
                          labelText: 'Search apps',
                          labelStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: const Color(0xFF101013),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child: Text(
                                  'No apps match your search.',
                                  style: TextStyle(color: Color(0xFF9A9AA3)),
                                ),
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final app = filtered[index];
                                  final label =
                                      app['app_label'] ?? 'Unknown App';
                                  final packageName =
                                      app['package_name'] ?? '';

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF101013),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: const Color(0xFF232329),
                                      ),
                                    ),
                                    child: ListTile(
                                      onTap: () => Navigator.pop(context, app),
                                      title: Text(
                                        label,
                                        style: const TextStyle(
                                          color: Color(0xFFF5F5F5),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      subtitle: Text(
                                        packageName,
                                        style: const TextStyle(
                                          color: Color(0xFF9A9AA3),
                                          fontSize: 12,
                                        ),
                                      ),
                                      trailing: const Icon(
                                        Icons.chevron_right,
                                        color: Color(0xFF9A9AA3),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
    return selected;
  }

  Future<void> _removeAllowedApp(String appIdentifier) async {
    try {
      setState(() {
        _isReplacingApps = true;
      });

      await _appPolicyService.removeAllowedAppFromHabit(
        habitId: widget.habitId,
        appIdentifier: appIdentifier,
      );

      await _loadPolicy();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Allowed app removed.')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isReplacingApps = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove allowed app: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isReplacingApps = false;
        });
      }
    }
  }

  Widget _buildSectionCard({
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17171A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: child,
    );
  }

  Widget _buildSectionTitle(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF9A9AA3),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeTile({
    required String value,
    required String title,
    required String subtitle,
  }) {
    final selected = _policyMode == value;

    return InkWell(
      onTap: _isSaving
          ? null
          : () {
              setState(() {
                _policyMode = value;
              });
            },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0x22F5F5F5) : const Color(0xFF101013),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFFF5F5F5)
                : const Color(0xFF232329),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? const Color(0xFFF5F5F5)
                  : const Color(0xFF9A9AA3),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFFF5F5F5),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF9A9AA3),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllowedAppCard(Map<String, dynamic> app) {
    final label = (app['app_label'] ?? 'Unknown app').toString();
    final identifier = (app['app_identifier'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101013),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF232329)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.apps_rounded,
            color: Color(0xFFF5F5F5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFF5F5F5),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  identifier,
                  style: const TextStyle(
                    color: Color(0xFF9A9AA3),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed:
                _isReplacingApps ? null : () => _removeAllowedApp(identifier),
            icon: const Icon(
              Icons.delete_outline,
              color: Color(0xFFFF8A80),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF5F5F5)),
      );
    }

    if (_error != null && !_supportsFocusPolicy) {
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF17171A),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF232329)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.habitTitle,
                style: const TextStyle(
                  color: Color(0xFFF5F5F5),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Focus policy only applies to focus verification habits.',
                style: const TextStyle(
                  color: Color(0xFFB3B3BB),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFFF8A80),
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(
                'Strictness',
                subtitle:
                    'Choose whether the user can stay only in Achievr or in Achievr plus selected apps.',
              ),
              _buildModeTile(
                value: 'achievr_only',
                title: 'Achievr only',
                subtitle:
                    'Only Achievr and screen off are allowed during the focus session.',
              ),
              _buildModeTile(
                value: 'allow_list',
                title: 'Allow selected app(s)',
                subtitle:
                    'Achievr, screen off, and up to 2 selected apps are valid during the focus session.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(
                'Grace period',
                subtitle:
                    'Grace is automatically derived from the task’s required time and cannot be edited manually.',
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF101013),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF232329)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Derived grace',
                      style: TextStyle(
                        color: Color(0xFF9A9AA3),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$_derivedGraceMinutes min ($_leaveGraceSeconds sec)',
                      style: const TextStyle(
                        color: Color(0xFFF5F5F5),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Rule: about 1 minute of grace for every 12 minutes of required task time.',
                      style: TextStyle(
                        color: Color(0xFFB3B3BB),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(
                'Allowed apps',
                subtitle: _policyMode == 'allow_list'
                    ? 'Only these apps are permitted besides Achievr. Maximum 2 apps.'
                    : 'Switch to allow-list mode to configure up to 2 habit-specific apps.',
              ),
              if (_policyMode != 'allow_list')
                const Text(
                  'This habit is currently in Achievr-only mode.',
                  style: TextStyle(
                    color: Color(0xFF9A9AA3),
                    fontSize: 13,
                  ),
                ),
              if (_policyMode == 'allow_list' && _allowedApps.isEmpty)
                const Text(
                  'No allowed apps added yet.',
                  style: TextStyle(
                    color: Color(0xFF9A9AA3),
                    fontSize: 13,
                  ),
                ),
              if (_policyMode == 'allow_list')
                ..._allowedApps.map(_buildAllowedAppCard),
              if (_policyMode == 'allow_list') ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        (_isReplacingApps ||
                                _isLoadingInstalledApps ||
                                _allowedApps.length >= 2)
                            ? null
                            : _addAllowedApp,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF5F5F5),
                      side: const BorderSide(color: Color(0xFF3A3A42)),
                    ),
                    icon: (_isReplacingApps || _isLoadingInstalledApps)
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: Text(
                      _isLoadingInstalledApps
                          ? 'Loading apps...'
                          : _allowedApps.length >= 2
                              ? 'Maximum apps reached'
                              : 'Choose allowed app',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _savePolicy,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF5F5F5),
              foregroundColor: Colors.black,
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text(
              'Save focus policy',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0C),
        title: const Text('Focus Policy'),
      ),
      body: _buildBody(),
    );
  }
}