import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smartify/core/errors/failures.dart';
import 'package:smartify/features/analytics/models/analytics_data_model.dart';

/// SMARTIFY Analytics Service
/// Queries server-authoritative grievance statistics and trends via Supabase RPC.
class AnalyticsService {
  final SupabaseClient? _supabaseClient;

  AnalyticsService({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient;

  SupabaseClient get _client {
    if (_supabaseClient != null) return _supabaseClient!;
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw const DatabaseFailure('Supabase client has not been initialized.');
    }
  }

  /// Fetches aggregated grievance analytics within optional date ranges & department scope
  Future<AnalyticsDataModel> fetchAnalytics({
    DateTime? startDate,
    DateTime? endDate,
    String? departmentId,
  }) async {
    try {
      final response = await _client.rpc<dynamic>(
        'get_grievance_analytics',
        params: {
          if (startDate != null) 'p_start_date': startDate.toIso8601String(),
          if (endDate != null) 'p_end_date': endDate.toIso8601String(),
          if (departmentId != null) 'p_department_id': departmentId,
        },
      );

      return AnalyticsDataModel.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      debugPrint('AnalyticsService.fetchAnalytics error: $e');
      throw DatabaseFailure(
        e.toString().replaceFirst(RegExp(r'^[A-Za-z]+Failure:\s*'), ''),
      );
    }
  }
}
