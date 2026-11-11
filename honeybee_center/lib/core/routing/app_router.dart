import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../pages/main_dashboard.dart';
import '../../pages/owner_shell.dart';

/// Returns the appropriate top-level dashboard widget for an authenticated
/// [AuthSession], routing by role:
///
///   main_admin  →  [OwnerShell]    (monitoring only)
///   co_admin    →  [MainDashboardPage]  (full operations)
///
/// Both paths are materialized as a [MaterialPageRoute] for use with
/// [Navigator.pushReplacement].
Widget routeForSession(AuthSession session) {
  return session.role == UserRole.mainAdmin
      ? OwnerShell(session: session)
      : MainDashboardPage(session: session);
}

/// Convenience: returns a [MaterialPageRoute] that builds [routeForSession].
MaterialPageRoute<void> routePageForSession(AuthSession session) {
  return MaterialPageRoute<void>(
    builder: (_) => routeForSession(session),
  );
}
