// lib/config/supabase_config.dart
// Honeybee Center — Supabase Configuration
// Target Project: honeybee-center-main (gvteqrtvpfujfrwrdohv)

class SupabaseConfig {
  /// Base URL for Honeybee Center Supabase project
  static const String url = 'https://gvteqrtvpfujfrwrdohv.supabase.co';

  /// Publishable anon key (safe for client application; RLS protects database tables)
  /// Can be passed via `--dart-define=SUPABASE_ANON_KEY=<key>` or set as default here.
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd2dGVxcnR2cGZ1amZyd3Jkb2h2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE2MzU2NTAsImV4cCI6MjEwNzIxMTY1MH0.mitShOcnabbAt58TCmdV3u1S2iD4YXSTP95JtDQEi6Y',
  );

  /// Helper to verify if credentials are configured
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
