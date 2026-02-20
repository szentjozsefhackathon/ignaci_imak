import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry_logging/sentry_logging.dart';

import 'env.dart';

export 'package:sentry_flutter/sentry_flutter.dart'
    show
        Sentry,
        SentryNavigatorObserver,
        SentryWidget,
        SentryWidgetsFlutterBinding;

bool get hasSentryDsn => Env.sentryDsn?.isNotEmpty ?? false;

Future<void> initSentry() async {
  if (Env.sentryDsn case final String dsn when dsn.isNotEmpty) {
    await SentryFlutter.init((options) {
      options.dsn = dsn;
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

      const serverAppPath = Env.serverAppPath;
      options.beforeSend = (event, hint) {
        // https://pub.dev/packages/sentry_dart_plugin#web
        if (serverAppPath != null &&
            serverAppPath != '' &&
            serverAppPath != '/') {
          event.exceptions = event.exceptions?.map((e) {
            final s = e.stackTrace;
            if (s != null) {
              return e
                ..stackTrace = SentryStackTrace(
                  frames: [
                    for (final f in s.frames)
                      f
                        ..absPath = f.absPath?.replaceFirst(
                          Env.serverUrl,
                          '${Env.serverUrl}/$serverAppPath',
                        ),
                  ],
                );
            }
            return e;
          }).toList();
        }
        return event;
      };
    });
  }
}
