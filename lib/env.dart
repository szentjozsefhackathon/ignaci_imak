import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(
  allowOptionalFields: true,
  useConstantCase: true,
  // ignore: avoid_redundant_argument_values
  environment: bool.fromEnvironment('CI'),
)
abstract class Env {
  @EnviedField(optional: false)
  static const String serverUrl = _Env.serverUrl;

  static Uri? _serverUri;
  static Uri get serverUri => _serverUri ??= Uri.parse(serverUrl);

  @EnviedField(optional: false)
  static const String serverCheckVersionsPath = _Env.serverCheckVersionsPath;

  @EnviedField(optional: false)
  static const String serverDownloadDataPath = _Env.serverDownloadDataPath;

  @EnviedField(optional: false)
  static const String serverMediaPathPrefix = _Env.serverMediaPathPrefix;

  @EnviedField()
  static const String? serverAppPath = _Env.serverAppPath;

  @EnviedField(defaultValue: 'dev')
  static const String sentryEnvironment = _Env.sentryEnvironment;

  @EnviedField(obfuscate: true)
  static final String? sentryDsn = _Env.sentryDsn;

  @EnviedField(defaultValue: '1.0')
  static const String sentryTracesSampleRate = _Env.sentryTracesSampleRate;

  @EnviedField(defaultValue: '1.0')
  static const String sentryProfilesSampleRate = _Env.sentryProfilesSampleRate;

  @EnviedField(defaultValue: '0.1')
  static const String sentrySessionSampleRate = _Env.sentrySessionSampleRate;

  @EnviedField(defaultValue: '1.0')
  static const String sentryOnErrorSampleRate = _Env.sentryOnErrorSampleRate;
}
