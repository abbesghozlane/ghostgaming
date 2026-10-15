import 'package:supabase_flutter/supabase_flutter.dart';

class CurrentRoleCache {
  static String? _cachedRole;

  static String? get role => _cachedRole;

  static bool get isCustomer => _cachedRole == 'customer';

  static bool get isStaff => _cachedRole != null && _cachedRole != 'customer';

  static void setRole(String? role) {
    if (role != null && role.isNotEmpty) {
      _cachedRole = role;
    }
  }

  static void clear() {
    _cachedRole = null;
  }

  /// Syncs cached role from current user metadata or venue_members
  static Future<String?> syncRole(SupabaseClient client) async {
    final user = client.auth.currentUser;
    if (user == null) {
      _cachedRole = null;
      return null;
    }
    final metaRole = user.userMetadata?['role'] as String?;
    if (metaRole != null && metaRole.isNotEmpty) {
      _cachedRole = metaRole;
      return metaRole;
    }
    try {
      final membership = await client
          .from('venue_members')
          .select('role')
          .eq('user_id', user.id)
          .eq('is_active', true)
          .order('created_at')
          .limit(1)
          .maybeSingle();
      final role = membership?['role'] as String?;
      if (role != null && role.isNotEmpty) {
        _cachedRole = role;
      }
      return role;
    } catch (_) {
      return _cachedRole;
    }
  }
}
