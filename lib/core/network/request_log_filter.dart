import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import 'api_routes.dart';

/// Endpoints whose request or response bodies carry credentials or tokens
/// (passwords, social identity JWTs, idToken/refreshToken pairs, FCM tokens). Exact-match
/// so non-credential auth endpoints (`/auth/searchUser`, `/auth/profile`,
/// `/auth/verify-email`, …) keep full logging.
const Set<String> _credentialPaths = {
  ApiRoutes.signIn,
  ApiRoutes.signUp,
  ApiRoutes.socialSignIn,
  ApiRoutes.refreshToken,
  ApiRoutes.forgotPassword,
  ApiRoutes.resetPassword,
  ApiRoutes.fcmToken,
};

/// Filter used by [PrettyDioLogger] to decide whether a request, response,
/// or error entry should be printed to the console.
///
/// Returns `false` (suppress the entry) only for the credential-bearing
/// endpoints in [_credentialPaths] — these must never land in logcat/Xcode
/// console/CI logs. Failures on the suppressed endpoints stay diagnosable
/// through the repository-level logging in the auth data layer.
bool shouldLogRequest(RequestOptions options, FilterArgs args) {
  return !_credentialPaths.contains(options.path);
}
