import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../../core/data/current_role_cache.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final bool? isStaff;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    this.isStaff,
  });

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    
    const staffOnlyRoutes = {
      '/home',
      '/reports',
      '/admin',
      '/activity',
      '/expenses',
      '/cash',
      '/employees',
    };

    final isCustomerByRole = CurrentRoleCache.isCustomer;
    final isStaffByRole = CurrentRoleCache.isStaff;

    final effectiveIsStaff = isStaff ??
        (isCustomerByRole
            ? false
            : isStaffByRole
                ? true
                : staffOnlyRoutes.contains(location));

    final items = effectiveIsStaff
        ? [
            {'label': 'Home', 'icon': Icons.home_rounded, 'route': '/home'},
            {
              'label': 'Postes',
              'icon': Icons.sports_esports_rounded,
              'route': '/posts',
            },
            {
              'label': 'Stock',
              'icon': Icons.shopping_bag_rounded,
              'route': '/inventory',
            },
            {
              'label': 'Rapports',
              'icon': Icons.bar_chart_rounded,
              'route': '/reports',
            },
            {'label': 'Admin', 'icon': Icons.person_rounded, 'route': '/admin'},
          ]
        : [
            {
              'label': 'Accueil',
              'icon': Icons.grid_view_rounded,
              'route': '/customer/home',
            },
            {
              'label': 'Postes',
              'icon': Icons.sports_esports_rounded,
              'route': '/posts',
            },
            {
              'label': 'Jeux',
              'icon': Icons.extension_rounded,
              'route': '/games',
            },
            {
              'label': 'Snack',
              'icon': Icons.fastfood_rounded,
              'route': '/inventory',
            },
            {
              'label': 'Profil',
              'icon': Icons.person_rounded,
              'route': '/customer/profile',
            },
          ];

    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: const Color(0xF20D0D1E),
        border: const Border(top: BorderSide(color: Color(0xFF1D1D3A), width: 1.5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x99000000),
            offset: Offset(0, -6),
            blurRadius: 24,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(items.length, (index) {
          final item = items[index];
          final isSelected = index == currentIndex;
          final color = isSelected ? AppColors.pink : const Color(0xFF8C8CA8);
          return Expanded(
            child: InkWell(
              onTap: () => context.go(item['route'] as String),
              child: SizedBox(
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item['icon'] as IconData,
                          size: isSelected ? 24 : 22,
                          color: color,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item['label'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    if (isSelected)
                      Positioned(
                        bottom: 6,
                        child: Container(
                          width: 20,
                          height: 3.5,
                          decoration: BoxDecoration(
                            color: AppColors.pink,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: const [
                              BoxShadow(color: AppColors.pink, blurRadius: 10),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
