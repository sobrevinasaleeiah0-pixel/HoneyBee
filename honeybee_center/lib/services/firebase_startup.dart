import 'dart:async';

import 'package:flutter/foundation.dart';

class FirebaseStartup {
  static const defaultTimeout = Duration(seconds: 12);

  static Future<bool> initialize({
    required Future<void> Function() initializeFirebase,
    required Future<void> Function() seedInitialData,
    Duration timeout = defaultTimeout,
  }) async {
    try {
      await initializeFirebase().timeout(timeout);
    } catch (error, stackTrace) {
      debugPrint('[FirebaseStartup] Firebase initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }

    try {
      await seedInitialData().timeout(timeout);
    } catch (error, stackTrace) {
      debugPrint('[FirebaseStartup] Firebase initial data seed failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    return true;
  }
}
