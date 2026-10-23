import 'package:flutter/material.dart';

/// SMARTIFY Semantic Multi-Token Color Palette
/// Academic Slate & Deep Emerald Theme (WCAG 2.2 AA Compliant)
class AppColors {
  AppColors._();

  // --- Brand & Identity ---
  static const Color primary = Color(0xFF0D9488); // Teal 600
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFCCFBF1); // Teal 100
  static const Color onPrimaryContainer = Color(0xFF115E59); // Teal 800

  static const Color primaryDark = Color(0xFF14B8A6); // Teal 500
  static const Color onPrimaryDark = Color(0xFF042F2E);
  static const Color primaryContainerDark = Color(0xFF134E4A); // Teal 900
  static const Color onPrimaryContainerDark = Color(0xFF5EEAD4); // Teal 300

  // --- Secondary & Authority Hierarchy ---
  static const Color secondary = Color(0xFF4F46E5); // Indigo 600
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFE0E7FF); // Indigo 100
  static const Color onSecondaryContainer = Color(0xFF3730A3); // Indigo 800

  static const Color secondaryDark = Color(0xFF818CF8); // Indigo 400
  static const Color onSecondaryDark = Color(0xFF1E1B4B);
  static const Color secondaryContainerDark = Color(0xFF312E81); // Indigo 900
  static const Color onSecondaryContainerDark = Color(0xFFC7D2FE); // Indigo 200

  // --- Surfaces & Backgrounds (Light Mode) ---
  static const Color backgroundLight = Color(0xFFF8FAFC); // Slate 50
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedLight = Color(0xFFFFFFFF);
  static const Color textPrimaryLight = Color(0xFF0F172A); // Slate 900
  static const Color textMutedLight = Color(0xFF64748B); // Slate 500
  static const Color borderLight = Color(0xFFE2E8F0); // Slate 200

  // --- Surfaces & Backgrounds (Dark Mode) ---
  static const Color backgroundDark = Color(0xFF0F172A); // Slate 900
  static const Color surfaceDark = Color(0xFF1E293B); // Slate 800
  static const Color surfaceElevatedDark = Color(0xFF334155); // Slate 700
  static const Color textPrimaryDark = Color(0xFFF8FAFC); // Slate 50
  static const Color textMutedDark = Color(0xFF94A3B8); // Slate 400
  static const Color borderDark = Color(0xFF334155); // Slate 700

  // --- Semantic Feedback & Complaint Statuses ---
  static const Color statusPending = Color(0xFFD97706); // Amber 600
  static const Color statusUnderReview = Color(0xFF2563EB); // Blue 600
  static const Color statusInProgress = Color(0xFF0284C7); // Sky 600
  static const Color statusEscalated = Color(0xFFEA580C); // Orange 600
  static const Color statusSlaBreached = Color(0xFFDC2626); // Red 600
  static const Color statusCutoffPaused =
      Color(0xFF7C3AED); // Purple 600 (20-day cutoff freeze)
  static const Color statusResolved = Color(0xFF059669); // Emerald 600
  static const Color statusRejected = Color(0xFF64748B); // Slate 500

  static const Color error = Color(0xFFDC2626); // Red 600
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFEE2E2); // Red 100
  static const Color onErrorContainer = Color(0xFF991B1B); // Red 800

  static const Color success = Color(0xFF059669); // Emerald 600
  static const Color onSuccess = Color(0xFFFFFFFF);
  static const Color successContainer = Color(0xFFD1FAE5); // Emerald 100
  static const Color onSuccessContainer = Color(0xFF065F46); // Emerald 800

  // --- Outlines & Dividers ---
  static const Color outline = Color(0xFF475569); // Slate 600
  static const Color outlineLight = Color(0xFFCBD5E1); // Slate 300
}
