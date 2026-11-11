import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'config/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'core/routing/app_router.dart';
import 'pages/login_page.dart';
import 'services/auth_service.dart';
import 'services/data_initializer.dart';
import 'services/firebase_startup.dart';
import 'widgets/supabase_startup_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch all uncaught Flutter framework errors so they print to console
  // instead of silently showing a white screen.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };

  runApp(const HoneybeeCenterApp());

  unawaited(
    FirebaseStartup.initialize(
      initializeFirebase: () async {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      },
      seedInitialData: DataInitializer.seedInitialData,
    ),
  );
}

class HoneybeeCenterApp extends StatefulWidget {
  const HoneybeeCenterApp({super.key});

  @override
  State<HoneybeeCenterApp> createState() => _HoneybeeCenterAppState();
}

class _HoneybeeCenterAppState extends State<HoneybeeCenterApp> {
  static const _supabaseStartupTimeout = Duration(seconds: 20);
  Future<void>? _supabaseInitializationAttempt;
  late Future<void> _supabaseStartup;

  @override
  void initState() {
    super.initState();
    _supabaseStartup = _initializeSupabase();
    ThemeNotifier.instance.addListener(() {
      setState(() {});
    });
  }

  Future<void> _initializeSupabase() {
    final existingAttempt = _supabaseInitializationAttempt;
    if (existingAttempt != null) {
      return existingAttempt.timeout(_supabaseStartupTimeout);
    }

    final attempt = _performSupabaseInitialization();
    _supabaseInitializationAttempt = attempt;
    unawaited(
      attempt.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (identical(_supabaseInitializationAttempt, attempt)) {
            _supabaseInitializationAttempt = null;
          }
        },
      ),
    );
    return attempt.timeout(_supabaseStartupTimeout);
  }

  Future<void> _performSupabaseInitialization() async {
    if (!SupabaseConfig.isConfigured) {
      throw StateError('Supabase URL or publishable key is not configured.');
    }

    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Honeybee Center',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeNotifier.instance.themeMode,
      home: SupabaseStartupGate(
        initialization: _supabaseStartup,
        onRetry: () {
          setState(() {
            _supabaseStartup = _initializeSupabase();
          });
        },
        child: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: AuthService().getCurrentSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Any error (network, Firebase 400, etc.) → show login page
        if (snapshot.hasError) {
          return const LoginPage();
        }

        final session = snapshot.data;
        if (session != null) {
          return routeForSession(session);
        }

        return const LoginPage();
      },
    );
  }
}
