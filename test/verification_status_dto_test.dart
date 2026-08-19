import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:consumer_flutter_app/data/models/verification_status_dto.dart';

void main() {
  group('VerificationStatusDto.tryParse', () {
    test('parses the 403 body the server sends for an unverified login', () {
      final status = VerificationStatusDto.tryParse({
        'username': 'alice',
        'verified': false,
        'message': "User hasn't verified email",
      });

      expect(status, isNotNull);
      expect(status!.username, 'alice');
      expect(status.verified, isFalse);
      expect(status.message, "User hasn't verified email");
    });

    test('parses an undecoded JSON string body', () {
      final status = VerificationStatusDto.tryParse(
        jsonEncode({'username': 'bob', 'verified': false, 'message': 'nope'}),
      );

      expect(status?.username, 'bob');
      expect(status?.verified, isFalse);
    });

    test('returns null for bodies without a verified flag', () {
      expect(VerificationStatusDto.tryParse('forbidden'), isNull);
      expect(VerificationStatusDto.tryParse({'message': 'forbidden'}), isNull);
      expect(VerificationStatusDto.tryParse(null), isNull);
      expect(VerificationStatusDto.tryParse(42), isNull);
    });

    test('reports verified: true so callers can skip the resend prompt', () {
      final status = VerificationStatusDto.tryParse({
        'username': 'carol',
        'verified': true,
      });

      expect(status?.verified, isTrue);
      expect(status?.message, isNull);
    });
  });
}
