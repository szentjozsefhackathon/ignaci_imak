import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:relative_time/relative_time.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry_logging/sentry_logging.dart';

import 'data/settings_data.dart';
import 'env.dart';
import 'notifications.dart';
import 'routes.dart';
import 'settings/dnd.dart' show DndProvider;
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

  // TODO: allow opt-out
  await SentryFlutter.init((options) {
    options.dsn = Env.sentryDsn;
    options.environment = Env.sentryEnvironment;

    // https://docs.sentry.io/platforms/dart/guides/flutter/data-management/data-collected/
    options.sendDefaultPii = true;
    options.enableLogs = true;
    options.addIntegration(LoggingIntegration());
    options.enableTimeToFullDisplayTracing = true;
    options.tracesSampleRate =
        double.tryParse(Env.sentryTracesSampleRate) ?? 1.0;
    options.profilesSampleRate =
        double.tryParse(Env.sentryProfilesSampleRate) ?? 1.0;
    options.replay.sessionSampleRate =
        double.tryParse(Env.sentrySessionSampleRate) ?? 0.1;
    options.replay.onErrorSampleRate =
        double.tryParse(Env.sentryOnErrorSampleRate) ?? 1.0;

    // https://docs.sentry.io/platforms/dart/guides/flutter/user-feedback/
    options.feedback.title = 'Hibajelzés';
    options.feedback.showName = true; // false?
    options.feedback.showEmail = true; // false?
    options.feedback.showBranding = false;
    options.feedback.showCaptureScreenshot = true;
    options.feedback.formTitle = 'Hibajelzés';
    options.feedback.messageLabel = 'Részletek';
    options.feedback.messagePlaceholder =
        'Pontosan mi nem működik? Mi lenne az elvárt?';
    options.feedback.isRequiredLabel = ' (kötelező)';
    options.feedback.successMessageText = 'Köszönjük a visszajelzést!';
    options.feedback.nameLabel = 'Név';
    options.feedback.namePlaceholder = '';
    options.feedback.emailLabel = 'E-mail cím';
    options.feedback.emailPlaceholder = '';
    options.feedback.submitButtonLabel = 'Küldés';
    options.feedback.cancelButtonLabel = 'Mégsem';
    options.feedback.validationErrorLabel = 'Ez nem lehet üres';
    options.feedback.captureScreenshotButtonLabel = 'Képernyőkép csatolása';
    options.feedback.removeScreenshotButtonLabel = 'Képernyőkép eltávolítása';
    options.feedback.takeScreenshotButtonLabel = 'Képernyőkép készítése';
  });

  runApp(SentryWidget(child: const IgnacioPrayersApp()));
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
      );
    },
  );
}
