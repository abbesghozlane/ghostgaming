import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_config.dart';
import '../../core/data/current_role_cache.dart';
import '../../core/offline/offline_sync_screen.dart';
import '../../features/auth/data/auth_state_refresh.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/dashboard/presentation/staff_home_screen.dart';
import '../../features/posts/presentation/posts_screen.dart';
import '../../features/games/presentation/game_store_screen.dart';
import '../../features/reservations/presentation/booking_screen.dart';
import '../../features/inventory/presentation/inventory_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/admin/presentation/admin_screen.dart';
import '../../features/customers/presentation/customer_home_screen.dart';
import '../../features/customers/presentation/customer_qr_scanner_screen.dart';
import '../../features/customers/presentation/customer_profile_screen.dart';
import '../../features/employees/presentation/employee_invitation_screen.dart';
import '../../features/employees/presentation/employee_management_screen.dart';
import '../../features/audit/presentation/audit_log_screen.dart';
import '../../features/expenses/presentation/expenses_screen.dart';
import '../../features/cash/presentation/cash_shift_screen.dart';
import '../../features/customers/presentation/customer_finance_screen.dart';
import '../../features/notifications/presentation/notification_inbox_screen.dart';
import '../../features/settings/presentation/venue_settings_screen.dart';
import '../../features/promotions/presentation/promotions_screen.dart';
import '../../features/loyalty/presentation/loyalty_screen.dart';
import '../../features/programs/presentation/programs_screen.dart';
import '../../features/invoices/presentation/invoice_history_screen.dart';
import '../../features/search/presentation/global_search_screen.dart';

RouteBase _smoothRoute(String path, Widget child) {
  return GoRoute(
    path: path,
    pageBuilder: (context, state) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final slideTween = Tween<Offset>(
          begin: const Offset(0.04, 0.0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic));

        final fadeTween = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut));

        return SlideTransition(
          position: animation.drive(slideTween),
          child: FadeTransition(
            opacity: animation.drive(fadeTween),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
    ),
  );
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: authStateRefresh,
  redirect: (context, state) async {
    final location = state.matchedLocation;
    final isAuthRoute =
        location == '/' || location == '/login' || location == '/signup';
    final isCustomerEntryRoute = location == '/customer/scan';
    final isStaffInvitationRoute = location == '/staff/invite';
    if (!SupabaseConfig.isConfigured) {
      return isAuthRoute || isStaffInvitationRoute ? null : '/login';
    }

    final isAuthenticated =
        Supabase.instance.client.auth.currentSession != null;
    if (!isAuthenticated) {
      return isAuthRoute || isCustomerEntryRoute || isStaffInvitationRoute
          ? null
          : '/login';
    }

    String? role;
    Map<String, dynamic> permissions = const {};
    try {
      final membership = await Supabase.instance.client
          .from('venue_members')
          .select('role, permissions')
          .eq('user_id', Supabase.instance.client.auth.currentUser!.id)
          .eq('is_active', true)
          .order('created_at')
          .limit(1)
          .maybeSingle();
      role = membership?['role'] as String?;
      CurrentRoleCache.setRole(role);
      permissions = Map<String, dynamic>.from(
        membership?['permissions'] as Map? ?? const {},
      );
    } on PostgrestException catch (error) {
      debugPrint('Vérification du rôle de navigation impossible : $error');
      return null;
    }

    if (isAuthRoute) {
      return role == 'customer'
          ? '/customer/home'
          : role == null
          ? '/signup'
          : '/home';
    }
    if (role == 'customer' &&
        !isCustomerEntryRoute &&
        !isStaffInvitationRoute &&
        location != '/customer/home' &&
        location != '/customer/profile' &&
        location != '/posts' &&
        location != '/games' &&
        location != '/inventory' &&
        location != '/booking' &&
        location != '/notifications' &&
        location != '/invoices' &&
        location != '/search' &&
        location != '/offline-sync') {
      return '/customer/home';
    }
    if (role != null && role != 'customer' && location == '/customer/home') {
      return '/home';
    }
    if (role == null &&
        !isCustomerEntryRoute &&
        !isStaffInvitationRoute &&
        location != '/signup') {
      return '/signup';
    }
    if (role == 'employee' && permissions['view_reports'] != true) {
      if (location == '/reports') {
        return '/home';
      }
    }
    if (location == '/admin' &&
        role != 'owner' &&
        role != 'manager' &&
        permissions['manage_staff'] != true &&
        permissions['manage_catalog'] != true &&
        permissions['manage_settings'] != true) {
      return '/home';
    }
    if (location == '/reports' &&
        role != 'owner' &&
        role != 'manager' &&
        permissions['view_reports'] != true) {
      return '/home';
    }
    if (location == '/inventory' &&
        role == 'employee' &&
        permissions['manage_stock'] != true) {
      return '/home';
    }
    return null;
  },
  routes: [
    _smoothRoute('/', const SplashScreen()),
    _smoothRoute('/login', const LoginScreen()),
    _smoothRoute('/signup', const SignupScreen()),
    _smoothRoute('/home', const StaffHomeScreen()),
    _smoothRoute('/posts', const PostsScreen()),
    _smoothRoute('/games', const GameStoreScreen()),
    _smoothRoute('/booking', const BookingScreen()),
    _smoothRoute('/inventory', const InventoryScreen()),
    _smoothRoute('/reports', const ReportsScreen()),
    _smoothRoute('/admin', const AdminScreen()),
    _smoothRoute('/employees', const EmployeeManagementScreen()),
    _smoothRoute('/activity', const AuditLogScreen()),
    _smoothRoute('/expenses', const ExpensesScreen()),
    _smoothRoute('/cash', const CashShiftScreen()),
    _smoothRoute('/customers', const CustomerFinanceScreen()),
    _smoothRoute('/notifications', const NotificationInboxScreen()),
    _smoothRoute('/invoices', const InvoiceHistoryScreen()),
    _smoothRoute('/search', const GlobalSearchScreen()),
    _smoothRoute('/offline-sync', const OfflineSyncScreen()),
    _smoothRoute('/settings', const VenueSettingsScreen()),
    _smoothRoute('/promotions', const PromotionsScreen()),
    _smoothRoute('/loyalty', const LoyaltyScreen()),
    _smoothRoute('/programs', const ProgramsScreen()),
    GoRoute(
      path: '/staff/invite',
      pageBuilder: (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        child: EmployeeInvitationScreen(token: state.uri.queryParameters['token']),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slideTween = Tween<Offset>(
            begin: const Offset(0.04, 0.0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic));
          final fadeTween = Tween<double>(
            begin: 0.0,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeOut));
          return SlideTransition(
            position: animation.drive(slideTween),
            child: FadeTransition(opacity: animation.drive(fadeTween), child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    ),
    _smoothRoute('/customer/home', const CustomerHomeScreen()),
    _smoothRoute('/customer/profile', const CustomerProfileScreen()),
    GoRoute(
      path: '/customer/scan',
      pageBuilder: (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        child: const CustomerQrScannerScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slideTween = Tween<Offset>(
            begin: const Offset(0.04, 0.0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic));
          final fadeTween = Tween<double>(
            begin: 0.0,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeOut));
          return SlideTransition(
            position: animation.drive(slideTween),
            child: FadeTransition(opacity: animation.drive(fadeTween), child: child),
          );
        },
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    ),
  ],
);
