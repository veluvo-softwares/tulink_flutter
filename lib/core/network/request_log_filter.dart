import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

/// Filter used by [PrettyDioLogger] to decide whether a request, response,
/// or error entry should be printed to the console.
///
/// Returns `false` (suppress logging) for any request whose
/// [RequestOptions.path] contains the substring `/auth` — this covers
/// `/auth/login`, `/auth/register`, `/auth/social`, `/auth/refresh-token`,
/// `/auth/forgot-password`, etc., regardless of any leading base-URL
/// segments. These endpoints carry credentials, social identity JWTs, or
/// auth tokens (idToken/refreshToken) in their request/response bodies,
/// which must never be printed to logcat/Xcode console/CI logs.
///
/// All other endpoints continue to be logged in full — auth failures remain
/// diagnosable via `AuthLogger` and repository-level logging instead.
bool shouldLogRequest(RequestOptions options, FilterArgs args) {
  return !options.path.contains('/auth');
}
