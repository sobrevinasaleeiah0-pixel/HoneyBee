import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:honeybee_center/services/firebase_startup.dart';

void main() {
  group('FirebaseStartup', () {
    test('seeds only after Firebase initializes successfully', () async {
      var initialized = false;
      var seeded = false;

      final result = await FirebaseStartup.initialize(
        initializeFirebase: () async {
          initialized = true;
        },
        seedInitialData: () async {
          expect(initialized, isTrue);
          seeded = true;
        },
      );

      expect(result, isTrue);
      expect(seeded, isTrue);
    });

    test('Firebase initialization failure skips seeding', () async {
      var seeded = false;

      final result = await FirebaseStartup.initialize(
        initializeFirebase: () async {
          throw StateError('Firebase unavailable');
        },
        seedInitialData: () async {
          seeded = true;
        },
      );

      expect(result, isFalse);
      expect(seeded, isFalse);
    });

    test('Firebase initialization timeout skips seeding', () async {
      var seeded = false;
      final neverCompletes = Completer<void>();

      final result = await FirebaseStartup.initialize(
        initializeFirebase: () => neverCompletes.future,
        seedInitialData: () async {
          seeded = true;
        },
        timeout: const Duration(milliseconds: 10),
      );

      expect(result, isFalse);
      expect(seeded, isFalse);
    });

    test(
      'seed failure does not mark initialized Firebase unavailable',
      () async {
        final result = await FirebaseStartup.initialize(
          initializeFirebase: () async {},
          seedInitialData: () async {
            throw StateError('Seed failed');
          },
        );

        expect(result, isTrue);
      },
    );
  });
}
