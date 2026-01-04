import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart' show MultiProvider, Selector;
import 'package:relative_time/relative_time.dart';
import 'package:timezone/data/latest_all.dart' as tzdb;
import 'package:timezone/timezone.dart'
    if (dart.library.js_interop) 'package:timezone/browser.dart'
    as tz;
import 'package:universal_io/universal_io.dart' show Platform;

import 'data/database.dart' show DatabaseProvider;
import 'data/preferences.dart';
import 'notifications.dart' show NotificationsProvider;
import 'routes.dart';
import 'sentry.dart';
import 'services.dart';
import 'settings/dnd.dart' show DndProvider;
import 'settings/focus_status.dart' show FocusStatusProvider;
import 'theme.dart';

void main() async {
  SentryWidgetsFlutterBinding.ensureInitialized();

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: ${record.message}');
  });

  if (kIsWeb) {
    usePathUrlStrategy();
  }
  Intl.defaultLocale = 'hu';

  tzdb.initializeTimeZones();
  final localTz = await FlutterTimezone.getLocalTimezone();
  final location = tz.getLocation(localTz.identifier);
  tz.setLocalLocation(location);
  Logger.root.fine('Local timezone: $location');

  final prefs = Preferences(
    await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    ),
  );
  if (prefs.sentryEnabled) {
    await initSentry();
  }

  runApp(SentryWidget(child: IgnacioPrayersApp(prefs: prefs)));
}

class IgnacioPrayersApp extends StatelessWidget {
  const IgnacioPrayersApp({super.key, required this.prefs});

  final Preferences prefs;

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      PreferencesProvider(prefs),
      if (!kIsWeb) ...[
        NotificationsProvider(),
        DatabaseProvider(),
        SyncServiceProvider(),
        if (Platform.isIOS) FocusStatusProvider(),
      ],
      DndProvider(),
    ],
    builder: (context, widget) => Selector<Preferences, AppThemeMode>(
      selector: (context, p) => p.themeMode,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'Ignáci imák',
        theme: AppTheme.lightTheme,
        darkTheme: themeMode == AppThemeMode.oled
            ? AppTheme.oledTheme
            : AppTheme.darkTheme, // Default dark theme
        themeMode: switch (themeMode) {
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark || AppThemeMode.oled => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        navigatorObservers: [SentryNavigatorObserver()],
        initialRoute: Routes.home,
        onGenerateRoute: Routes.onGenerateRoute,
        onUnknownRoute: Routes.onUnknownRoute,
        localizationsDelegates: const [
          RelativeTimeLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('hu')],
      ),
    ),
  );
}
