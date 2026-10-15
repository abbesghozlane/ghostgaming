import 'package:flutter_test/flutter_test.dart';
import 'package:ghostgaming/core/utils/venue_time_zone.dart';
import 'package:ghostgaming/features/invoices/data/invoice_repository.dart';

void main() {
  test('invoice parses session classification and local date', () {
    final invoice = InvoiceRecord.fromJson({
      'id': 'invoice-1',
      'number': 42,
      'total': 900.5,
      'session_id': 'session-1',
      'order_id': null,
      'created_at': '2026-10-05T10:15:00Z',
    });

    expect(invoice.number, 42);
    expect(invoice.total, 900.5);
    expect(invoice.isSessionInvoice, isTrue);
    expect(
      invoice.createdAt,
      VenueTimeZone.parse('2026-10-05T10:15:00Z', 'Africa/Algiers'),
    );
  });

  test('standalone product sale is classified separately', () {
    final invoice = InvoiceRecord.fromJson({
      'id': 'invoice-2',
      'number': 43,
      'total': 150,
      'session_id': null,
      'order_id': 'order-1',
      'created_at': '2026-10-05T10:15:00Z',
    });

    expect(invoice.isSessionInvoice, isFalse);
  });

  test('malformed invoice totals and timestamps are rejected', () {
    final base = {
      'id': 'invoice-3',
      'number': 44,
      'total': 120,
      'session_id': null,
      'order_id': 'order-2',
      'created_at': '2026-10-05T10:15:00Z',
    };

    expect(
      () => InvoiceRecord.fromJson({...base, 'total': double.nan}),
      throwsFormatException,
    );
    expect(
      () => InvoiceRecord.fromJson({...base, 'created_at': 'not-a-date'}),
      throwsFormatException,
    );
  });
}
