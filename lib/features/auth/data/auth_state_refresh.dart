import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_config.dart';

class AuthStateRefresh extends ChangeNotifier {
  StreamSubscription<AuthState>? _subscription;

  void start() {
    if (!SupabaseConfig.isConfigured || _subscription != null) return;
    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => notifyListeners(),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final authStateRefresh = AuthStateRefresh();
