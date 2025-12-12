import 'dart:io' show Platform;

import 'package:do_not_disturb/do_not_disturb.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

class DndProvider extends ChangeNotifier with WidgetsBindingObserver {
  DndProvider() {
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
  }

  static final _log = Logger('DndProvider');
  final _dndPlugin = DoNotDisturbPlugin();

  bool? _hasAccess;
  bool get hasAccess => _hasAccess ?? false;

  InterruptionFilter? _statusBeforeEnable;

  Future<void> _checkAccess() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    bool? hasAccess;
    try {
      hasAccess = await _dndPlugin.isNotificationPolicyAccessGranted();
    } catch (e, s) {
      _log.severe('Failed to check notification policy access', e, s);
    }
    if (_hasAccess != hasAccess) {
      _hasAccess = hasAccess;
      notifyListeners();
    }
  }

  Future<void> allowAlarmsOnly() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    if (_hasAccess ?? false) {
      _statusBeforeEnable = await _dndPlugin.getDNDStatus();
      await _dndPlugin.setInterruptionFilter(InterruptionFilter.alarms);
    }
  }

  Future<void> restoreOriginal() async {
    if (_statusBeforeEnable == null) {
      return;
    }
    await _dndPlugin.setInterruptionFilter(_statusBeforeEnable!);
  }

  void openSettings() => _dndPlugin.openDndSettings();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccess();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class DndSwitchListTile extends StatelessWidget {
  const DndSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final hasAccess = context.select<DndProvider, bool>((dnd) => dnd.hasAccess);

    if (hasAccess) {
      return SwitchListTile(
        title: const Text('Ne zavarjanak'),
        subtitle: const Text(
          'Értesítések és egyéb hangok némítása az ima alatt',
        ),
        value: value,
        onChanged: onChanged,
      );
    }

    return ListTile(
      title: const Text('Ne zavarjanak'),
      subtitle: Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text: 'Értesítések és egyéb hangok némítása az ima alatt\n',
            ),
            TextSpan(
              text: 'Hiányzó engedélyek, érintsd meg itt a beállításhoz!',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ),
      isThreeLine: true,
      onTap: () => context
          .read<DndProvider>()
          ._dndPlugin
          .openNotificationPolicyAccessSettings(),
    );
  }
}
