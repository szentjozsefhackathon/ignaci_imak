import 'dart:io' show Platform;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart';
import 'theme.dart' show kThemeSeedColor;

export 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show DateTimeComponents;
export 'package:timezone/timezone.dart' show TZDateTime, local;

typedef _Android = AndroidFlutterLocalNotificationsPlugin;
typedef _IOS = IOSFlutterLocalNotificationsPlugin;
typedef _MacOS = MacOSFlutterLocalNotificationsPlugin;

class Notifications with ChangeNotifier {
  static final _log = Logger('Notifications');
  final _n = FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    'emlekezteto',
    'Emlékeztető értesítések',
    importance: Importance.high,
  );

  static final _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _androidChannel.id,
      _androidChannel.name,
      color: kThemeSeedColor,
      priority: Priority.high,
      importance: _androidChannel.importance,
      category: AndroidNotificationCategory.reminder,
    ),
    // enable presentation on iOS/macOS so notifications are visible (including foreground)
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    ),
    macOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    ),
    linux: const LinuxNotificationDetails(
      resident: true,
      urgency: LinuxNotificationUrgency.normal,
    ),
    windows: const WindowsNotificationDetails(
      scenario: WindowsNotificationScenario.reminder,
    ),
  );

  bool? _hasPermission;
  bool? get hasPermission => _hasPermission;

  Future<void> initialize() async {
    // ensure tz database loaded before any TZDateTime usage
    tz.initializeTimeZones();

    final initialized = await _n.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(defaultActionName: 'Megnyitás'),
        windows: WindowsInitializationSettings(
          appName: 'Ignáci imák',
          appUserModelId: 'hu.jezsuita.ima.ignaci',
          guid: '349fd997-d211-4ac7-9690-8ed1bb184196',
        ),
      ),
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
    );

    if (initialized != true) {
      return;
    }

    // Create Android notification channel
    if (Platform.isAndroid) {
      await _n
          .resolvePlatformSpecificImplementation<_Android>()
          ?.createNotificationChannel(_androidChannel);
    }

    // On iOS & macOS, always request permission explicitly
    if (Platform.isIOS || Platform.isMacOS) {
      await requestPermissions();
    }

    // After requesting, check and cache the permission result
    _hasPermission = await _checkPermissions();
    notifyListeners();
  }

  void _onDidReceiveNotificationResponse(NotificationResponse details) {
    _log.fine('onDidReceiveNotificationResponse payload: ${details.payload}');
  }

  Future<bool?> _checkPermissions() async {
    bool? result;
    if (Platform.isAndroid) {
      final impl = _n.resolvePlatformSpecificImplementation<_Android>();
      result = await impl?.areNotificationsEnabled();
      if (result == true) {
        result = await impl?.canScheduleExactNotifications();
      }
    } else if (Platform.isIOS) {
      result = await _n
          .resolvePlatformSpecificImplementation<_IOS>()
          ?.checkPermissions()
          .then((r) => r?.isEnabled);
    } else if (Platform.isMacOS) {
      result = await _n
          .resolvePlatformSpecificImplementation<_MacOS>()
          ?.checkPermissions()
          .then((r) => r?.isEnabled);
    } else {
      throw UnimplementedError(
        'checkPermissions is not implemented on ${Platform.operatingSystem}',
      );
    }
    return result;
  }

  Future<bool?> requestPermissions() async {
    bool? result;
    if (Platform.isAndroid) {
      final impl = _n.resolvePlatformSpecificImplementation<_Android>();
      result = await impl?.requestNotificationsPermission();
      if (result == true) {
        result = await impl?.requestExactAlarmsPermission();
      }
    } else if (Platform.isIOS) {
      result = await _n
          .resolvePlatformSpecificImplementation<_IOS>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isMacOS) {
      result = await _n
          .resolvePlatformSpecificImplementation<_MacOS>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else {
      throw UnimplementedError(
        'requestPermissions is not implemented on ${Platform.operatingSystem}',
      );
    }

    if (result != null && result != _hasPermission) {
      _hasPermission = result;
      notifyListeners();
    }
    return result;
  }

  Future<List<PendingNotificationRequest>> get scheduledNotifications =>
      _n.pendingNotificationRequests();

  Future<void> scheduleNotificationAt({
    required TZDateTime dateTime,
    required DateTimeComponents? repeat,
  }) async {
    final pending = await scheduledNotifications;
    final maxId = pending.map((n) => n.id).maxOrNull ?? 0;
    await _n.zonedSchedule(
      maxId + 1,
      'Ignáci ima',
      'Itt az ideje egy kicsit elcsendesedni 🙏',
      dateTime,
      _notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: repeat,
      payload: '${repeat?.name ?? ''}::${dateTime.toIso8601String()}',
    );
    notifyListeners();
  }

  Future<void> showTest() async {
    final pending = await scheduledNotifications;
    final maxId = pending.map((n) => n.id).maxOrNull ?? 0;
    await _n.show(
      maxId + 1,
      'Ignáci ima',
      'Ez egy teszt értesítés',
      _notificationDetails,
    );
  }

  Future<void> cancel(int id) async {
    await _n.cancel(id);
    notifyListeners();
  }

  Future<void> cancelAll() async {
    await _n.cancelAll();
    notifyListeners();
  }
}

class NotificationsSwitchListTile extends StatelessWidget {
  const NotificationsSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final notifications = context.watch<Notifications>();
    final hasPermission = notifications.hasPermission;
    if (hasPermission == null) {
      return const SizedBox();
    }
    if (!hasPermission) {
      return ListTile(
        title: const Text('Emlékeztető értesítések'),
        subtitle: Text(
          'Hiányzó engedélyek, érintsd meg itt a beállításhoz!',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        onTap: notifications.requestPermissions,
      );
    }
    return SwitchListTile(
      title: const Text('Emlékeztető értesítések'),
      value: value,
      onChanged: (v) {
        onChanged(v);
        if (!v) {
          notifications.cancelAll();
        }
      },
    );
  }
}

const _kRepeatTypes = {
  DateTimeComponents.time: 'minden nap',
  DateTimeComponents.dayOfWeekAndTime: 'minden hét',
  DateTimeComponents.dayOfMonthAndTime: 'minden hónap',
  DateTimeComponents.dateAndTime: 'minden év',
};

final _kMonthFormat = DateFormat.MMMM();
final _kWeekdayFormat = DateFormat.EEEE();

class NotificationsList extends StatelessWidget {
  const NotificationsList({super.key});

  Widget _buildAdd(BuildContext context, Notifications notifications) {
    final hasPermission = notifications.hasPermission;
    if (hasPermission == null) {
      return const SizedBox();
    }

    return ListTile(
      title: const Text('Emlékeztető hozzáadása'),
      leading: const Icon(Icons.add_rounded),
      enabled: hasPermission,
      onTap: () async {
        final result = await showModalBottomSheet<_AddBottomSheetResult>(
          context: context,
          builder: (context) => _AddBottomSheet(),
        );
        if (context.mounted && result != null) {
          await notifications.scheduleNotificationAt(
            dateTime: result.dateTime,
            repeat: result.repeat,
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifications = context.watch<Notifications>();
    return FutureBuilder(
      future: notifications.scheduledNotifications,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || data.isEmpty) {
          return _buildAdd(context, notifications);
        }
        return Column(
          children: [
            _buildAdd(context, notifications),
            ...data.map((n) {
              final [repeatName, dateTimeStr] = n.payload!.split('::');
              final repeat = DateTimeComponents.values.singleWhereOrNull(
                (c) => c.name == repeatName,
              );
              final dateTime = DateTime.parse(dateTimeStr);
              return ListTile(
                leading: const SizedBox(),
                title: Text(
                  [
                    _kRepeatTypes[repeat],
                    if (repeat == DateTimeComponents.dateAndTime)
                      _kMonthFormat.format(dateTime),
                    if (repeat == DateTimeComponents.dayOfWeekAndTime)
                      _kWeekdayFormat.format(dateTime),
                    if (repeat == DateTimeComponents.dayOfMonthAndTime ||
                        repeat == DateTimeComponents.dateAndTime)
                      '${dateTime.day}. napján',
                    '${TimeOfDay.fromDateTime(dateTime).format(context)}-kor',
                  ].whereType<String>().join(' '),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  tooltip: 'Törlés',
                  onPressed: () => notifications.cancel(n.id),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _AddBottomSheetResult {
  _AddBottomSheetResult({required this.dateTime, required this.repeat});

  final TZDateTime dateTime;
  final DateTimeComponents repeat;
}

class _AddBottomSheet extends StatefulWidget {
  @override
  State<_AddBottomSheet> createState() => _AddBottomSheetState();
}

class _AddBottomSheetState extends State<_AddBottomSheet> {
  DateTimeComponents _repeat = DateTimeComponents.time;
  late TZDateTime _dateTime;

  @override
  void initState() {
    super.initState();
    // Ensure we have a valid TZDateTime even if timezone DB wasn't initialized yet.
    try {
      _dateTime = TZDateTime.now(local);
    } catch (_) {
      tz.initializeTimeZones();
      _dateTime = TZDateTime.now(local);
    }
  }

  String _monthLabel([int? month]) => _kMonthFormat.format(
    month == null ? _dateTime : _dateTime.copyWith(month: month),
  );

  String _weekdayLabel([int? weekday]) => _kWeekdayFormat.format(
    weekday == null ? _dateTime : _dateTime.copyWithWeekday(weekday),
  );

  Widget _chipWithText(Widget chip, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 8,
    children: [chip, Text(text)],
  );

  @override
  Widget build(BuildContext context) {
    final ml = MaterialLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Emlékeztető hozzáadása',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              PopupMenuButton(
                itemBuilder: (_) => DateTimeComponents.values
                    .map(
                      (d) => PopupMenuItem(
                        value: d,
                        child: Text(_kRepeatTypes[d]!),
                      ),
                    )
                    .toList(growable: false),
                onSelected: (d) => setState(() => _repeat = d),
                child: Chip(label: Text(_kRepeatTypes[_repeat]!)),
              ),
              if (_repeat == DateTimeComponents.dateAndTime)
                PopupMenuButton(
                  itemBuilder: (_) =>
                      List.generate(DateTime.monthsPerYear, (i) => i + 1)
                          .map(
                            (month) => PopupMenuItem(
                              value: month,
                              child: Text(_monthLabel(month)),
                            ),
                          )
                          .toList(growable: false),
                  onSelected: (month) {
                    setState(
                      () => _dateTime = TZDateTime.from(
                        _dateTime.copyWith(month: month),
                        local,
                      ),
                    );
                  },
                  child: Chip(label: Text(_monthLabel())),
                ),
              if (_repeat == DateTimeComponents.dayOfWeekAndTime)
                PopupMenuButton(
                  itemBuilder: (_) =>
                      List.generate(
                            DateTime.daysPerWeek,
                            (i) => i + ml.firstDayOfWeekIndex,
                          )
                          .map(
                            (offset) => PopupMenuItem(
                              value: offset,
                              child: Text(_weekdayLabel(offset)),
                            ),
                          )
                          .toList(growable: false),
                  onSelected: (offset) {
                    setState(
                      () => _dateTime = TZDateTime.from(
                        _dateTime.copyWithWeekday(offset),
                        local,
                      ),
                    );
                  },
                  child: Chip(label: Text(_weekdayLabel())),
                )
              else if (_repeat == DateTimeComponents.dayOfMonthAndTime ||
                  _repeat == DateTimeComponents.dateAndTime)
                _chipWithText(
                  PopupMenuButton(
                    itemBuilder: (_) => List.generate(31, (i) => i + 1)
                        .map(
                          (day) =>
                              PopupMenuItem(value: day, child: Text('$day.')),
                        )
                        .toList(growable: false),
                    onSelected: (day) {
                      setState(
                        () => _dateTime = TZDateTime.from(
                          _dateTime.copyWith(day: day),
                          local,
                        ),
                      );
                    },
                    child: Chip(label: Text('${_dateTime.day}.')),
                  ),
                  'napján',
                ),
              _chipWithText(
                ActionChip(
                  onPressed: () async {
                    final timeOfDay = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_dateTime),
                    );
                    if (mounted && timeOfDay != null) {
                      setState(
                        () => _dateTime = TZDateTime.from(
                          _dateTime.copyWith(
                            hour: timeOfDay.hour,
                            minute: timeOfDay.minute,
                          ),
                          local,
                        ),
                      );
                    }
                  },
                  label: Text(
                    TimeOfDay.fromDateTime(_dateTime).format(context),
                  ),
                ),
                '-kor',
              ),
            ],
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(ml.cancelButtonLabel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  _AddBottomSheetResult(dateTime: _dateTime, repeat: _repeat),
                ),
                child: Text(ml.okButtonLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension DateTimeExtensions on DateTime {
  DateTime copyWithWeekday(int weekday) =>
      copyWith(day: day + weekday - this.weekday);
}
