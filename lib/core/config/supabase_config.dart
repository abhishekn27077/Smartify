import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// SMARTIFY Supabase Client Configuration
/// Safely manages connection parameters via compile-time --dart-define or fallback constants.
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ypxhpoqkwvujwaogkkcq.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_YbsnG-Vhwqc4Fd_Cpt7-CQ_1UlbqA53',
  );

  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  /// Initializes Supabase connection with graceful offline fallback
  static Future<void> initialize() async {
    try {
      if (url.isNotEmpty && anonKey.isNotEmpty) {
        await Supabase.initialize(
          url: url,
          // ignore: deprecated_member_use
          anonKey: anonKey,
          debug: kDebugMode,
        );
        _isInitialized = true;
        debugPrint('Supabase successfully initialized.');
      }
    } catch (e) {
      debugPrint(
          'Supabase initialization caught: $e. Operating in resilient offline/demo mode.');
      _isInitialized = false;
    }
  }
}
