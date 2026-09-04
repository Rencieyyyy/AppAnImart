/// Turns any thrown object into a short sentence a normal person can read.
///
/// Nothing technical ever reaches the screen: no error codes, no SQL or
/// PostgREST text, no stack traces, no class names. Every value returned by
/// this file is a hand-written sentence — raw error text is only ever used to
/// *choose* between those sentences (and to `debugPrint` for developers).
///
/// When an error can't be explained, the user instead gets a short reference
/// code and the real error is logged to `public.client_errors`, so a developer
/// can look up what actually happened on a phone they've never touched. See
/// `supabase/migrations/20260723000000_client_error_log.sql`.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart';

/// App version recorded with each logged error, so a report can be tied to a
/// release. Keep in sync with `version:` in pubspec.yaml.
const String kAppVersion = '1.0.0+1';

/// The catch-all shown when we can't say anything more specific.
const String kGenericErrorMessage = 'Something went wrong. Please try again.';

/// Shown when the device looks offline or the request timed out.
const String kOfflineMessage =
    'No internet connection. Please check your network and try again.';

/// Shown when the server refuses the action (RLS / permission denied).
const String kNotAllowedMessage =
    'You are not allowed to do that right now. Please try again later.';

/// Shown when the session is gone or expired.
const String kSignedOutMessage = 'Please log in again to continue.';

/// Converts [error] into a safe, user-facing message.
///
/// Pass a [fallback] that describes the action that failed in plain words —
/// e.g. `'Could not save your profile. Please try again.'`. It is used
/// whenever the error has no friendlier meaning we can explain.
///
/// [action] names what the user was trying to do (`'save_profile'`,
/// `'publish_listing'`, …). It is only ever sent to the error log, never
/// shown, and it is what makes a logged row readable at a glance.
///
/// An error we *can* explain returns its sentence and nothing is logged — the
/// user already knows what to do about a wrong password or a dead connection.
/// An error we can't explain returns the [fallback] plus a reference code and
/// quietly records the real failure for developers.
String friendlyError(Object? error,
    {String fallback = kGenericErrorMessage, String? action}) {
  final explained = _explain(error, fallback);
  if (explained != null) return explained;
  return _unexplained(error, fallback: fallback, action: action);
}

/// Message for a Supabase auth failure (login, sign-up, password reset).
///
/// Only known cases get a specific sentence; anything else falls back to a
/// reference code, so an unexpected auth message is never echoed verbatim.
String friendlyAuthError(AuthException error,
    {String fallback = kGenericErrorMessage, String? action}) {
  return _explainAuth(error) ??
      _unexplained(error, fallback: fallback, action: action);
}

/// The sentence for an error we understand, or null when we don't.
String? _explain(Object? error, String fallback) {
  // Nothing actually failed — the caller had no error object to explain.
  if (error == null) return fallback;

  if (_looksOffline(error)) return kOfflineMessage;

  if (error is AuthException) return _explainAuth(error);
  if (error is PostgrestException) return _explainPostgrest(error);
  if (error is StorageException) return _explainStorage(error);

  return null;
}

/// Builds the message for a failure we can't explain: the plain [fallback]
/// plus a short code, with the real error logged under that same code.
String _unexplained(Object? error, {required String fallback, String? action}) {
  final ref = _newReference();
  final message = '$fallback (Ref: $ref)';
  _logError(error, ref: ref, action: action ?? 'unknown', shown: message);
  return message;
}

String? _explainAuth(AuthException error) {
  final m = error.message.toLowerCase();

  if (_looksOffline(error)) return kOfflineMessage;
  if (m.contains('invalid login') || m.contains('invalid credentials')) {
    return 'Wrong email or password. Please try again.';
  }
  if (m.contains('email not confirmed')) {
    return 'Please confirm your email first, then log in.';
  }
  if (m.contains('already registered') || m.contains('already exists')) {
    return 'That email is already registered. Please log in instead.';
  }
  if (m.contains('invalid email') || m.contains('unable to validate email')) {
    return 'Please enter a valid email address.';
  }
  if (m.contains('password') && m.contains('at least')) {
    return 'Your password is too short. Please use at least 8 characters.';
  }
  if (m.contains('weak password')) {
    return 'Please choose a stronger password.';
  }
  if (m.contains('token has expired') ||
      m.contains('expired') ||
      m.contains('invalid token') ||
      m.contains('otp')) {
    return 'That code is wrong or has expired. Please request a new one.';
  }
  if (m.contains('rate limit') ||
      m.contains('too many') ||
      m.contains('for security purposes')) {
    return 'Too many tries. Please wait a moment and try again.';
  }
  if (m.contains('session') || m.contains('jwt') || m.contains('not signed')) {
    return kSignedOutMessage;
  }
  if (m.contains('user not found')) {
    return 'No account found with that email.';
  }
  return null;
}

/// Database errors. The app's own server-side guards raise plain sentences
/// (Postgres code `P0001`) that are written for users — those are passed
/// through. Everything else is a technical fault the user can't act on, so it
/// is left unexplained and logged.
String? _explainPostgrest(PostgrestException error) {
  final code = (error.code ?? '').trim();
  final message = error.message.trim();

  if (code == 'P0001' && _looksHumanWritten(message)) return message;

  switch (code) {
    case '23505': // unique violation
      return 'That has already been submitted.';
    case '42501': // insufficient privilege
    case 'PGRST301': // JWT problem
      return kNotAllowedMessage;
    case '23503': // foreign key violation
      return 'That item is no longer available.';
    case '57014': // statement timeout
      return 'This is taking too long. Please try again.';
  }

  final m = message.toLowerCase();
  if (m.contains('row-level security') || m.contains('permission denied')) {
    return kNotAllowedMessage;
  }
  if (m.contains('jwt') || m.contains('not authenticated')) {
    return kSignedOutMessage;
  }
  return null;
}

/// File upload/download errors.
String? _explainStorage(StorageException error) {
  final m = error.message.toLowerCase();
  if (m.contains('exceeded the maximum') || m.contains('too large')) {
    return 'That file is too big. Please pick a smaller one.';
  }
  if (m.contains('mime') || m.contains('content type')) {
    return 'That file type is not supported. Please pick a JPG or PNG image.';
  }
  if (m.contains('not authorized') ||
      m.contains('unauthorized') ||
      m.contains('row-level security')) {
    return kNotAllowedMessage;
  }
  return null;
}

/// True when the failure is a connectivity problem rather than a real error.
///
/// Matched on text so it works without importing `dart:io` (which is not
/// available on every platform Flutter builds for).
bool _looksOffline(Object error) {
  final m = error.toString().toLowerCase();
  return m.contains('socketexception') ||
      m.contains('failed host lookup') ||
      m.contains('network is unreachable') ||
      m.contains('connection refused') ||
      m.contains('connection closed') ||
      m.contains('connection reset') ||
      m.contains('connection terminated') ||
      m.contains('timeoutexception') ||
      m.contains('timed out') ||
      m.contains('clientexception') ||
      m.contains('handshakeexception') ||
      m.contains('no address associated');
}

/// A rough check that a server message is a sentence meant for people, not a
/// technical dump. Guards against a raw driver message sneaking through.
bool _looksHumanWritten(String message) {
  if (message.isEmpty || message.length > 160) return false;
  final m = message.toLowerCase();
  const technicalMarkers = [
    '{',
    '}',
    'exception',
    'select ',
    'insert ',
    'update ',
    'delete ',
    'null value',
    'relation ',
    'column ',
    'constraint',
    'pgrst',
    'sqlstate',
    'stack',
    '://',
    '_id',
  ];
  return !technicalMarkers.any(m.contains);
}

// ── Reference codes & error logging ────────────────────────────────────────

/// Unambiguous alphabet: no 0/O or 1/I, so a code read aloud over the phone or
/// typed into support chat survives the trip.
const String _refAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

final Random _refRandom = Random();

/// Short code the user sees ("Ref: A7K2QF") and the log row is stored under.
String _newReference() => List.generate(
      6,
      (_) => _refAlphabet[_refRandom.nextInt(_refAlphabet.length)],
    ).join();

/// How many errors one app run may report. A screen stuck in a retry loop
/// should not spend the user's data on log inserts; the server enforces its
/// own limit too (see the client_errors_guard trigger).
const int _maxLogsPerSession = 20;
int _loggedThisSession = 0;

/// Records an unexplained failure against [ref]. Fire-and-forget by design:
/// the caller is already handling a failure, so this must never throw, never
/// block the UI, and never replace the original error with a logging one.
void _logError(Object? error, {
  required String ref,
  required String action,
  required String shown,
}) {
  // Always visible to a developer with the phone attached, even if the insert
  // below never lands (offline, RLS, table missing).
  debugPrint('[$ref] $action failed: $error');

  if (error == null) return;
  if (_loggedThisSession >= _maxLogsPerSession) return;
  _loggedThisSession++;

  // No await: the message is already on screen by the time this resolves.
  unawaited(_insertErrorRow(
    ref: ref,
    action: action,
    shown: shown,
    detail: error.toString(),
    code: _errorCode(error),
  ));
}

Future<void> _insertErrorRow({
  required String ref,
  required String action,
  required String shown,
  required String detail,
  required String? code,
}) async {
  try {
    await supabase.from('client_errors').insert({
      'ref': ref,
      'action': action,
      'shown': shown,
      // The server clamps this too; trimming here saves the upload.
      'detail': detail.length > 2000 ? detail.substring(0, 2000) : detail,
      'error_code': code,
      'platform': defaultTargetPlatform.name,
      'app_version': kAppVersion,
    });
  } catch (e) {
    // Logging the log failure would recurse. A dropped report is acceptable;
    // a crash inside error handling is not.
    debugPrint('Could not record error $ref: $e');
  }
}

/// The machine-readable code behind an error, when it has one.
String? _errorCode(Object error) {
  if (error is PostgrestException) return error.code;
  if (error is AuthException) return error.statusCode;
  if (error is StorageException) return error.statusCode;
  return null;
}
