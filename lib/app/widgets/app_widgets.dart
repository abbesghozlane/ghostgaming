import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.bg,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: -120,
          right: -95,
          child: _Glow(
            color: AppColors.primary.withValues(alpha: 0.26),
            size: 330,
          ),
        ),
        Positioned(
          top: 300,
          left: -150,
          child: _Glow(
            color: AppColors.pink.withValues(alpha: 0.14),
            size: 310,
          ),
        ),
        Positioned(
          bottom: -170,
          right: -90,
          child: _Glow(
            color: const Color(0xFF3A2A9A).withValues(alpha: 0.2),
            size: 340,
          ),
        ),
      ],
    ),
  );
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({
    super.key,
    this.title = 'GHOST',
    this.subtitle = 'GAMING',
    this.fontSize = 19,
  });

  final String title;
  final String subtitle;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final height = fontSize * 2.2;
    return Image.asset(
      'assets/images/logo.png',
      height: height < 24 ? 24 : height,
      fit: BoxFit.contain,
    );
  }
}

class AppScreenTitle extends StatelessWidget {
  const AppScreenTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 24,
                letterSpacing: -0.5,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({super.key, this.onBack, this.trailing});

  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      AppSurface(
        borderRadius: 15,
        padding: const EdgeInsets.all(10),
        onTap: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        },
        child: const Icon(Icons.arrow_back_rounded, size: 20),
      ),
      const Expanded(child: Center(child: AppBrandLogo(fontSize: 16))),
      SizedBox(width: 48, child: trailing),
    ],
  );
}

class AppSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final bool isSelected;
  final double borderRadius;

  const AppSurface({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.isSelected = false,
    this.borderRadius = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(0.35, -1),
          end: Alignment(-0.35, 1),
          colors: [AppColors.surface1, AppColors.surface2],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isSelected
              ? Colors.purple.withValues(alpha: 0.7)
              : AppColors.line,
          width: isSelected ? 1.5 : 1.0,
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0x66000000), // rgba(0,0,0,0.4)
            offset: Offset(0, 2),
            blurRadius: 6,
          ),
          const BoxShadow(
            color: Color(0xB2000000), // rgba(0,0,0,0.7)
            offset: Offset(0, 16),
            blurRadius: 28,
            spreadRadius: -10,
          ),
          BoxShadow(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.07),
            offset: const Offset(0, 1),
            blurRadius: 0,
            spreadRadius: 0,
          ),
          if (isSelected)
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.55),
              offset: const Offset(0, 12),
              blurRadius: 30,
              spreadRadius: -6,
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16.0),
            child: child,
          ),
        ),
      ),
    );
  }
}

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isGhost;
  final Widget? icon;
  final Color? textColor;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isGhost = false,
    this.icon,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        gradient: isGhost
            ? null
            : const LinearGradient(
                colors: [Color(0xFF7A2FD6), Color(0xFFD12BD1)],
              ),
        borderRadius: BorderRadius.circular(16),
        border: isGhost ? Border.all(color: AppColors.line) : null,
        boxShadow: isGhost
            ? [
                const BoxShadow(
                  color: Colors.black45,
                  offset: Offset(0, 10),
                  blurRadius: 20,
                  spreadRadius: -8,
                ),
              ]
            : [
                BoxShadow(
                  color: const Color(0xFFBE32DC).withValues(alpha: 0.55),
                  offset: const Offset(0, 10),
                  blurRadius: 24,
                  spreadRadius: -4,
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.25),
                  offset: const Offset(0, 1),
                  blurRadius: 0,
                  spreadRadius: 0,
                ),
              ],
        color: isGhost ? AppColors.surface1 : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: 8)],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor ?? Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  final String hintText;
  final TextEditingController? controller;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const AppTextField({
    super.key,
    required this.hintText,
    this.controller,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      borderRadius: 16,
      padding: EdgeInsets.zero,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        child: Row(
          children: [
            if (prefixIcon != null) ...[
              IconTheme(
                data: const IconThemeData(color: Color(0xFF8B8CAB), size: 18),
                child: prefixIcon!,
              ),
              const SizedBox(width: 11),
            ],
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: obscureText,
                keyboardType: keyboardType,
                onChanged: onChanged,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF767894),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (suffixIcon != null) ...[
              const SizedBox(width: 11),
              IconTheme(
                data: const IconThemeData(color: Color(0xFF8B8CAB), size: 18),
                child: suffixIcon!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
