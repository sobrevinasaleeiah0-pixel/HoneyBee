import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honeybee_center/services/database_service.dart';

void main() {
  test('DatabaseService can be constructed before Firebase initializes', () {
    expect(() => DatabaseService(), returnsNormally);
  });

  test(
    'scanner stream reports unavailable Firebase as a stream error',
    () async {
      if (Firebase.apps.isNotEmpty) {
        markTestSkipped('The test process already initialized Firebase.');
      }

      await expectLater(
        DatabaseService().getScanResultsStream(),
        emitsError(isA<StateError>()),
      );
    },
  );
}
