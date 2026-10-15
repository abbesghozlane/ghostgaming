import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/features/customers/domain/customer_qr_token.dart';

void main() {
  group('CustomerQrToken.fromScannedValue', () {
    const token = '0123456789abcdef0123456789abcdef';

    test('accepts the post QR token', () {
      expect(CustomerQrToken.fromScannedValue(token), token);
    });

    test('extracts the token from a QR link', () {
      expect(
        CustomerQrToken.fromScannedValue(
          'https://gaming.example/customer/link?token=$token',
        ),
        token,
      );
    });

    test('accepts custom post codes and tokens', () {
      expect(CustomerQrToken.fromScannedValue('Poste 1'), 'Poste 1');
      expect(CustomerQrToken.fromScannedValue('12345'), '12345');
    });

    test('rejects empty values', () {
      expect(CustomerQrToken.fromScannedValue(''), isNull);
    });
  });
}
