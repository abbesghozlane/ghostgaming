import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:window_manager/window_manager.dart';

import 'app/theme/app_theme.dart';
import 'app/router/app_router.dart';
import 'app/widgets/app_widgets.dart';
import 'core/offline/offline_operation_queue.dart';
import 'core/offline/offline_sync_screen.dart';
import 'core/supabase/supabase_config.dart';
import 'features/auth/data/auth_state_refresh.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  debugPrint('Handling a background message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1366, 768),
      minimumSize: Size(900, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: 'Ghost Gaming',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  await initializeDateFormatting('fr_FR');
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground message received: ${message.notification?.title}');
    });
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  if (SupabaseConfig.isConfigured) {
    await SupabaseConfig.initialize();
    await OfflineOperationQueue.initialize(Supabase.instance.client);
  }
  authStateRefresh.start();
  runApp(const GhostGamingApp());
}

class GhostGamingApp extends StatelessWidget {
  const GhostGamingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Ghost Gaming',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: appRouter,
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          const AmbientBackground(),
          Column(
            children: [
              if (SupabaseConfig.isConfigured) const OfflineQueueBanner(),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          ),
        ],
      ),
    );
  }
}
