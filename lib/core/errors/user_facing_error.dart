import 'failure.dart';

const String networkErrorMessage =
    'Check your internet connection and try again.';
const String genericErrorMessage = 'Something went wrong. Please try again.';

/// Converts technical failures into safe, concise copy for the UI.
///
/// Full failures remain available to logs and Crashlytics; this function is
/// only for text rendered to a user.
String userFacingErrorMessage(Object? error) {
  if (error is NetworkFailure) return networkErrorMessage;

  final text = switch (error) {
    Failure failure => '${failure.message} ${failure.details ?? ''}',
    null => '',
    _ => error.toString(),
  }.toLowerCase();

  const networkSignals = <String>[
    'network',
    'internet',
    'offline',
    'connection error',
    'connection problem',
    'failed to connect',
    'no route to host',
    'socketexception',
    'timed out',
    'timeout',
  ];
  if (networkSignals.any(text.contains)) return networkErrorMessage;
  return genericErrorMessage;
}
