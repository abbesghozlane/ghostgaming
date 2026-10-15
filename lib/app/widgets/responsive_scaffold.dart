import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'app_bottom_nav.dart';
import '../theme/app_theme.dart';
import '../../core/data/current_role_cache.dart';

class ResponsiveScaffold extends StatelessWidget {
  final int currentIndex;
  final bool? isStaff;
  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Color? backgroundColor;

  const ResponsiveScaffold({
    super.key,
    required this.currentIndex,
    this.isStaff,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;

    if (!isDesktop) {
      // Mobile Layout: standard Scaffold with bottomNavigationBar
      return Scaffold(
        backgroundColor: backgroundColor ?? Colors.transparent,
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: AppBottomNav(
          currentIndex: currentIndex,
          isStaff: isStaff,
        ),
      );
    } else {
      // Desktop Layout: Sidebar / Navigation Rail on the left, Content on the right
      final effectiveIsStaff = isStaff ?? CurrentRoleCache.isStaff;
      final items = effectiveIsStaff
          ? [
              {'label': 'Home', 'icon': Icons.home_rounded, 'route': '/home'},
              {'label': 'Postes', 'icon': Icons.sports_esports_rounded, 'route': '/posts'},
              {'label': 'Stock', 'icon': Icons.shopping_bag_rounded, 'route': '/inventory'},
              {'label': 'Rapports', 'icon': Icons.bar_chart_rounded, 'route': '/reports'},
              {'label': 'Admin', 'icon': Icons.person_rounded, 'route': '/admin'},
            ]
          : [
              {'label': 'Accueil', 'icon': Icons.grid_view_rounded, 'route': '/customer/home'},
              {'label': 'Postes', 'icon': Icons.sports_esports_rounded, 'route': '/posts'},
              {'label': 'Jeux', 'icon': Icons.extension_rounded, 'route': '/games'},
              {'label': 'Snack', 'icon': Icons.fastfood_rounded, 'route': '/inventory'},
              {'label': 'Profil', 'icon': Icons.person_rounded, 'route': '/customer/profile'},
            ];

      return Scaffold(
        backgroundColor: backgroundColor ?? Colors.transparent,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        body: Row(
          children: [
            // Desktop Sidebar
            Container(
              width: 260,
              decoration: const BoxDecoration(
                color: Color(0xF20D0D1E),
                border: Border(right: BorderSide(color: Color(0xFF1D1D3A), width: 1.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App Brand / Logo Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Row(
                      children: [
                        Image.asset('assets/images/logo.png', height: 32, fit: BoxFit.contain),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'GHOST GAMING',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'DESKTOP SUITE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Color(0xFF1D1D3A), height: 1),
                  const SizedBox(height: 12),
                  // Navigation Items
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isSelected = index == currentIndex;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () {
                                final route = item['route'] as String;
                                GoRouter.of(context).go(route);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.pink.withValues(alpha: 0.15) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? AppColors.pink.withValues(alpha: 0.4) : Colors.transparent,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      item['icon'] as IconData,
                                      size: 20,
                                      color: isSelected ? AppColors.pink : const Color(0xFF8C8CA8),
                                    ),
                                    const SizedBox(width: 14),
                                    Text(
                                      item['label'] as String,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                        color: isSelected ? Colors.white : const Color(0xFF8C8CA8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Bottom info / version footer
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'v1.0.0 • Desktop Ready',
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                  ),
                ],
              ),
            ),
            // Main Content Area
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }
}
