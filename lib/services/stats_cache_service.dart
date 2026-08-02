import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Redis cache API (`tsys-api`) üzerinden istatistik yükler.
/// `CACHE_API_URL` yoksa veya istek başarısızsa doğrudan Supabase RPC'ye düşer.
class StatsCacheService {
  StatsCacheService._();

  static SupabaseClient get _client => SupabaseService.client;

  static String? get _cacheApiBase {
    final raw = dotenv.env['CACHE_API_URL']?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  /// Admin veya müdür istatistik paketi.
  /// Dönen map: `rows`, `trendRows`, `personnelRatings`, `cached` (bool?).
  static Future<Map<String, dynamic>> loadDashboardStats({
    required bool isAdmin,
  }) async {
    final fromApi = await _tryLoadFromCacheApi();
    if (fromApi != null) return fromApi;
    return _loadDirect(isAdmin: isAdmin);
  }

  static Future<Map<String, dynamic>?> _tryLoadFromCacheApi() async {
    final base = _cacheApiBase;
    final session = _client.auth.currentSession;
    if (base == null || session == null) return null;

    try {
      final res = await http
          .get(
            Uri.parse('$base/api/stats'),
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body);
      if (body is! Map<String, dynamic>) return null;
      if (body['rows'] is! List) return null;

      return {
        'rows': List<Map<String, dynamic>>.from(
          (body['rows'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        ),
        'trendRows': List<Map<String, dynamic>>.from(
          ((body['trendRows'] as List?) ?? const []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        ),
        'personnelRatings': List<Map<String, dynamic>>.from(
          ((body['personnelRatings'] as List?) ?? const []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        ),
        'cached': body['cached'] == true,
      };
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _loadDirect({required bool isAdmin}) async {
    final statsRpc = isAdmin ? 'get_admin_stats' : 'get_manager_stats';
    final trendRpc = isAdmin ? 'get_admin_resolution_trend' : 'get_manager_resolution_trend';
    final results = await Future.wait([
      _client.rpc(statsRpc),
      _client.rpc(trendRpc),
      _client.rpc('get_personnel_ratings'),
    ]);
    return {
      'rows': List<Map<String, dynamic>>.from(results[0] as List),
      'trendRows': List<Map<String, dynamic>>.from(results[1] as List),
      'personnelRatings': List<Map<String, dynamic>>.from(results[2] as List),
      'cached': false,
    };
  }

  /// Ana sayfa mini KPI için yalnızca durum satırları.
  static Future<List<Map<String, dynamic>>> loadStatsRows({
    required bool isAdmin,
  }) async {
    final pack = await loadDashboardStats(isAdmin: isAdmin);
    return List<Map<String, dynamic>>.from(pack['rows'] as List);
  }
}
