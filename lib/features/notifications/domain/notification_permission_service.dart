import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_widgets.dart';

class NotificationPermissionService {
  static const _storage = FlutterSecureStorage();
  static const _keyPermissionGranted = 'notification_permission_granted';
  static const _keyPermissionPrompted = 'notification_permission_prompted';

  /// Checks if notification permissions are already granted or handled.
  /// If granted/prompted, does nothing.
  /// If not yet prompted or disabled, prompts the user gracefully.
  static Future<void> checkAndPromptIfNeeded(BuildContext context) async {
    final granted = await _storage.read(key: _keyPermissionGranted);
    final prompted = await _storage.read(key: _keyPermissionPrompted);

    // If already granted, don't prompt!
    if (granted == 'true' || prompted == 'true') {
      return;
    }

    if (!context.mounted) return;

    // Show a professional, branded permission sheet
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _NotificationPermissionSheet(),
    );

    if (result == true) {
      await _storage.write(key: _keyPermissionGranted, value: 'true');
      try {
        final messaging = FirebaseMessaging.instance;
        final settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          final token = await messaging.getToken();
          final userId = Supabase.instance.client.auth.currentUser?.id;
          if (token != null && userId != null) {
            await Supabase.instance.client.from('profiles').update({
              'fcm_token': token,
            }).eq('id', userId);
          }
        }
      } catch (e) {
        debugPrint('FCM permission error: $e');
      }
    }
    await _storage.write(key: _keyPermissionPrompted, value: 'true');
  }

  /// Mark permission explicitly as granted
  static Future<void> setPermissionGranted(bool granted) async {
    await _storage.write(
      key: _keyPermissionGranted,
      value: granted ? 'true' : 'false',
    );
    await _storage.write(key: _keyPermissionPrompted, value: 'true');
  }

  /// Reset permission state (for testing or re-check)
  static Future<void> resetPermissionState() async {
    await _storage.delete(key: _keyPermissionGranted);
    await _storage.delete(key: _keyPermissionPrompted);
  }
}

class _NotificationPermissionSheet extends StatelessWidget {
  const _NotificationPermissionSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
      decoration: const BoxDecoration(
        color: Color(0xFF121226),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: Color(0xFF26264F), width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 30,
            offset: Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.pink.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.pink.withValues(alpha: 0.4)),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              size: 38,
              color: AppColors.pink,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Activer les notifications',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Restez informé en temps réel de vos sessions de jeu, fin de temps, confirmations de réservations et suivis de commandes.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 26),
          AppButton(
            label: 'Activer les notifications',
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Plus tard',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
