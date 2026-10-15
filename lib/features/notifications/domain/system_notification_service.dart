import 'package:flutter/services.dart';

class SystemNotificationService {
  /// Displays a system notification alert with sound and haptic vibration feedback.
  static Future<void> triggerAlert({
    required String title,
    required String body,
  }) async {
    try {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }
}
