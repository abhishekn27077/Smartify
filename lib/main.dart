import 'package:flutter/material.dart';
import 'package:smartify/app.dart';
import 'package:smartify/core/config/supabase_config.dart';

/// SMARTIFY Application Entrypoint
/// Initializes services, crash zones, and core provider dependencies.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase client
  await SupabaseConfig.initialize();

  runApp(const SmartifyApp());
}
