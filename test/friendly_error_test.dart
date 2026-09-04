import 'package:ani_mart/friendly_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The rule these tests protect: a user never sees error codes, JSON, SQL or
/// class names — only a plain sentence, plus a reference code when the app
/// could not explain what went wrong.
void main() {
  // Anything a raw error dump would contain.
  const technical = [
    'PGRST',
    'Exception',
    'coerce',
    '{',
    '}',
    'jwt',
    'row-level',
    'null value',
    'SQLSTATE',
  ];

  void expectNothingTechnical(String message) {
    for (final marker in technical) {
      expect(message.toLowerCase(), isNot(contains(marker.toLowerCase())),
          reason: 'user-facing message leaked "$marker": $message');
    }
  }

  final refPattern = RegExp(r'\(Ref: [23456789A-HJ-NP-Z]{6}\)$');

  group('explained errors', () {
    test('a dropped connection reads as an offline message, with no code', () {
      final message = friendlyError(
        Exception('SocketException: Failed host lookup: supabase.co'),
        action: 'save_profile',
        fallback: 'Could not save your profile. Please try again.',
      );

      expect(message, kOfflineMessage);
      expect(message, isNot(matches(refPattern)));
      expectNothingTechnical(message);
    });

    test('a wrong password says so plainly', () {
      final message = friendlyAuthError(
        const AuthException('Invalid login credentials'),
        action: 'login',
        fallback: 'Could not log you in. Please try again.',
      );

      expect(message, 'Wrong email or password. Please try again.');
      expect(message, isNot(matches(refPattern)));
    });

    test('our own server guard (P0001) speaks to the user directly', () {
      final message = friendlyError(
        const PostgrestException(
          message: 'This listing is already reserved for another buyer.',
          code: 'P0001',
        ),
        action: 'submit_offer',
        fallback: 'Could not send your offer. Please try again.',
      );

      expect(message, 'This listing is already reserved for another buyer.');
      expect(message, isNot(matches(refPattern)));
    });

    test('a P0001 message that is really a technical dump is not shown', () {
      final message = friendlyError(
        const PostgrestException(
          message: 'null value in column "seller_id" violates constraint',
          code: 'P0001',
        ),
        action: 'submit_offer',
        fallback: 'Could not send your offer. Please try again.',
      );

      expectNothingTechnical(message);
      expect(message, startsWith('Could not send your offer.'));
      expect(message, matches(refPattern));
    });
  });

  group('unexplained errors', () {
    test('the PGRST116 dump users used to see becomes a plain sentence', () {
      final message = friendlyError(
        const PostgrestException(
          message: 'Cannot coerce the result to a single JSON object',
          code: 'PGRST116',
          details: 'The result contains 0 rows',
        ),
        action: 'save_shop_details',
        fallback: 'Could not save your shop details. Please try again.',
      );

      expectNothingTechnical(message);
      expect(message, startsWith('Could not save your shop details.'));
      expect(message, matches(refPattern),
          reason: 'an unexplained failure must give the user a code to quote');
    });

    test('a bare unknown error still gets a sentence and a code', () {
      final message = friendlyError(
        StateError('bad state'),
        action: 'publish_listing',
        fallback: 'Could not post your listing. Please try again.',
      );

      expectNothingTechnical(message);
      expect(message, matches(refPattern));
    });

    test('each failure gets its own reference code', () {
      final codes = <String>{};
      for (var i = 0; i < 25; i++) {
        final message = friendlyError(StateError('boom'),
            action: 'publish_listing', fallback: 'Could not post your listing.');
        codes.add(refPattern.firstMatch(message)!.group(0)!);
      }

      // Codes come from a 32^6 space; 25 draws colliding would mean the
      // generator isn't random.
      expect(codes.length, 25);
    });

    test('reference codes avoid characters users confuse when reading aloud',
        () {
      for (var i = 0; i < 50; i++) {
        final message = friendlyError(StateError('boom'),
            action: 'publish_listing', fallback: 'Could not post your listing.');
        final code = refPattern.firstMatch(message)!.group(0)!;
        expect(code, isNot(anyOf(contains('0'), contains('O'),
            contains('1'), contains('I'))));
      }
    });
  });

  test('a null error returns the caller\'s sentence untouched', () {
    expect(
      friendlyError(null, fallback: 'Could not save your profile.'),
      'Could not save your profile.',
    );
  });
}
