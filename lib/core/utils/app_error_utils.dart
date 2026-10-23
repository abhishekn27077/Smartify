import 'package:flutter/foundation.dart';

/// SMARTIFY User-Facing Error Sanitizer
/// Translates low-level database, PostgREST, and network exceptions into
/// polite, secure, and actionable institutional guidance.
class AppErrorUtils {
  AppErrorUtils._();

  static String cleanErrorMessage(dynamic error) {
    if (error == null) return 'An unexpected error occurred.';
    
    final raw = error.toString();
    debugPrint('[APP_ERROR_DIAGNOSTIC] Raw error intercepted: $raw');

    // 1. Network / Connectivity Failures
    if (raw.contains('SocketException') ||
        raw.contains('ClientException') ||
        raw.contains('Failed host lookup') ||
        raw.contains('network_error') ||
        raw.contains('Connection refused')) {
      return 'Unable to reach the campus server. Please check your network connection and try again.';
    }

    // 2. Row Level Security / Permission Denials
    if (raw.contains('42501') ||
        raw.contains('row-level security') ||
        raw.contains('violates row-level security policy') ||
        raw.contains('Unauthorized') ||
        raw.contains('Forbidden')) {
      return 'You are not authorized to perform this action.';
    }

    // 3. Unconfigured Next Tier Forwarding
    if (raw.contains('No Level 2 authority') ||
        raw.contains('no next-tier') ||
        raw.contains('not configured for this department') ||
        raw.contains('next authority level is not configured')) {
      return 'This case cannot be forwarded because the next authority level is not configured.';
    }

    // 4. Schema / Technical PostgREST artifacts
    if (raw.contains('from_authority_id') ||
        raw.contains('PostgrestException') ||
        raw.contains('PGRST') ||
        raw.contains('syntax error') ||
        raw.contains('relation')) {
      return 'A system configuration error occurred. Central Governance has been notified.';
    }

    // 5. Clean standard Exception / Failure prefixes
    return raw
        .replaceFirst(RegExp(r'^[A-Za-z]+Failure:\s*'), '')
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^StateError\s*\(\s*'), '')
        .replaceFirst(RegExp(r'^PostgrestException\(message:\s*'), '')
        .replaceAll(RegExp(r',\s*code:.*$'), '')
        .replaceAll(RegExp(r'\)$'), '')
        .trim();
  }
}
