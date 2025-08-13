import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:relative_time/relative_time.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'data/settings_data.dart';
import 'notifications.dart';
import 'routes.dart';
import 'settings/dnd.dart' show DndProvider;
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: ${record.message}');
  });

  if (kIsWeb) {
    usePathUrlStrategy();
  }
  Intl.defaultLocale = 'hu';

  await SentryFlutter.init((options) {
    options.dsn = const String.fromEnvironment('SENTRY_DSN');
    options.environment = const String.fromEnvironment(
      'SENTRY_ENVIRONMENT',
      defaultValue: 'dev',
    );
    // https://docs.sentry.io/platforms/dart/guides/flutter/data-management/data-collected/
    options.sendDefaultPii = true;
    options.enableLogs = true;
    options.tracesSampleRate =
        double.tryParse(
          const String.fromEnvironment('SENTRY_TRACES_SAMPLE_RATE'),
        ) ??
        1.0;
    options.profilesSampleRate =
        double.tryParse(
          const String.fromEnvironment('SENTRY_PROFILES_SAMPLE_RATE'),
        ) ??
        1.0;
    options.replay.sessionSampleRate =
        double.tryParse(
          const String.fromEnvironment('SENTRY_SESSION_SAMPLE_RATE'),
        ) ??
        0.1;
    options.replay.onErrorSampleRate =
        double.tryParse(
          const String.fromEnvironment('SENTRY_ON_ERROR_SAMPLE_RATE'),
        ) ??
        1.0;
  }, appRunner: () => runApp(SentryWidget(child: const IgnacioPrayersApp())));
  // TODO: Remove this line after sending the first sample event to sentry.
  await Sentry.captureException(StateError('This is a sample exception.'));
}

class IgnacioPrayersApp extends StatelessWidget {
  const IgnacioPrayersApp({super.key});

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => SettingsData()..load()),
      if (!kIsWeb)
        ChangeNotifierProvider(
          lazy: false,
          create: (_) => Notifications()..initialize(),
        ),
      ChangeNotifierProvider(create: (_) => DndProvider()),
    ],
    builder: (context, widget) {
      final settings = context.watch<SettingsData>();
      return MaterialApp(
        title: 'Ignáci imák',
        theme: AppTheme.createTheme(Brightness.light),
        darkTheme: AppTheme.createTheme(Brightness.dark),
        themeMode: settings.themeMode,
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
      );
    },
  );
}
