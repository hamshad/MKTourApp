import 'package:flutter_test/flutter_test.dart';
import 'package:mktours/features/ride/excess_settlement_sheet.dart';

/// Succeeded-as-cash-confirm regression tests (excess-sheet-stuck-on-cash-succeeded).
///
/// The backend emits `payment:succeeded` (NOT `payment:excessCashConfirmed`)
/// for the driver-cash round-trip, with copy like "Cash payment confirmed by
/// driver! Your ride is fully settled." The sheet's succeeded handler must
/// recognise that copy as our settlement (authoritative close even if the
/// re-fetch still shows the stale balance), while a generic capture
/// ("Payment succeeded") must keep the re-fetch-or-stay-open guard so a
/// mid-trip base-fare capture never closes the sheet.
void main() {
  group('isCashConfirmMessage', () {
    test('backend driver-cash-confirm copy → true', () {
      expect(
        ExcessSettlementSheet.isCashConfirmMessage(
          'Cash payment confirmed by driver! Your ride is fully settled.',
        ),
        isTrue,
      );
    });

    test('case-insensitive cash + settled variant → true', () {
      expect(
        ExcessSettlementSheet.isCashConfirmMessage(
          'CASH received — ride FULLY SETTLED, thank you!',
        ),
        isTrue,
      );
    });

    test('generic succeeded copy → false (base-fare guard intact)', () {
      expect(
        ExcessSettlementSheet.isCashConfirmMessage('Payment succeeded.'),
        isFalse,
      );
      expect(
        ExcessSettlementSheet.isCashConfirmMessage(
          'Excess paid successfully! Your ride is fully settled.',
        ),
        isFalse,
      );
    });

    test('cash without confirm/settled → false', () {
      expect(
        ExcessSettlementSheet.isCashConfirmMessage(
          'Please hand cash to your driver.',
        ),
        isFalse,
      );
    });

    test('null / empty → false', () {
      expect(ExcessSettlementSheet.isCashConfirmMessage(null), isFalse);
      expect(ExcessSettlementSheet.isCashConfirmMessage(''), isFalse);
      expect(ExcessSettlementSheet.isCashConfirmMessage('   '), isFalse);
    });
  });
}
