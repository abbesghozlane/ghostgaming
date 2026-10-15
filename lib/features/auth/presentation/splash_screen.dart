import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );

    _controller.forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigateToNextScreen();
      }
    });

    // Fallback timer at 4.2 seconds
    Future.delayed(const Duration(milliseconds: 4200), () {
      _navigateToNextScreen();
    });
  }

  void _navigateToNextScreen() {
    if (mounted && !_navigated) {
      _navigated = true;
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _navigateToNextScreen,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black,
          child: SafeArea(
            child: Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final stageWidth = math.min(
                        constraints.maxWidth * 0.94,
                        900.0,
                      );
                      final stageHeight = stageWidth / (1600.0 / 728.0);
                      final value = _controller.value;

                      // 1. SKULL ROLL & SHAKE
                      // Roll: 0ms -> 2400ms [0.0 -> 0.5714]
                      double rollProgress = 0.0;
                      if (value <= 0.5714) {
                        final t = (value / 0.5714).clamp(0.0, 1.0);
                        rollProgress =
                            const Cubic(0.2, 0.7, 0.3, 1.0).transform(t);
                      } else {
                        rollProgress = 1.0;
                      }

                      final skullRollX =
                          (1.0 - rollProgress) * (-3.8 * stageWidth);
                      final skullRollRot =
                          (1.0 - rollProgress) * (-4 * math.pi);

                      // Shake: 2400ms -> 2800ms [0.5714 -> 0.6667]
                      double shakeScale = 1.0;
                      double shakeRot = 0.0;
                      if (value > 0.5714 && value <= 0.6667) {
                        final t = (value - 0.5714) / (0.6667 - 0.5714);
                        if (t < 0.5) {
                          final st = t * 2.0;
                          shakeScale = 1.0 + (0.12 * st);
                          shakeRot = -0.07 * st;
                        } else {
                          final st = (t - 0.5) * 2.0;
                          shakeScale = 1.12 - (0.12 * st);
                          shakeRot = -0.07 * (1.0 - st);
                        }
                      }

                      // 2. GLOW
                      // Glow in: 2400ms -> 3000ms [0.5714 -> 0.7143]
                      // Glow out: 3000ms -> 3600ms [0.7143 -> 0.8571]
                      double glowOpacity = 0.0;
                      double glowScale = 1.0;
                      if (value > 0.5714 && value <= 0.7143) {
                        final t = (value - 0.5714) / (0.7143 - 0.5714);
                        glowOpacity = Curves.easeOut.transform(t);
                        glowScale = 1.0 + 0.6 * Curves.easeOut.transform(t);
                      } else if (value > 0.7143 && value <= 0.8571) {
                        final t = (value - 0.7143) / (0.8571 - 0.7143);
                        glowOpacity = 1.0 - 0.65 * t;
                        glowScale = 1.6 - 0.6 * t;
                      } else if (value > 0.8571) {
                        glowOpacity = 0.35;
                        glowScale = 1.0;
                      }

                      // 3. TEXT OUT ("GHOST" left & right)
                      // 2700ms -> 3800ms [0.6429 -> 0.9048]
                      double textOpacity = 0.0;
                      double textScale = 0.05;
                      if (value > 0.6429) {
                        final t =
                            ((value - 0.6429) / (0.9048 - 0.6429)).clamp(0.0, 1.0);
                        textOpacity = t;
                        textScale =
                            const Cubic(0.2, 1.2, 0.4, 1.0).transform(t);
                      }

                      // 4. "GAMING" TEXT
                      // 3400ms -> 4200ms [0.8095 -> 1.0]
                      double gmOpacity = 0.0;
                      double gmScaleX = 0.1;
                      double gmScaleY = 0.02;
                      if (value > 0.8095) {
                        final t =
                            ((value - 0.8095) / (1.0 - 0.8095)).clamp(0.0, 1.0);
                        gmOpacity = t;
                        final curved =
                            const Cubic(0.2, 1.2, 0.4, 1.0).transform(t);
                        gmScaleX = 0.1 + (0.9 * curved);
                        gmScaleY = 0.02 + (0.98 * curved);
                      }

                      return SizedBox(
                        width: stageWidth,
                        height: stageHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // 1. Glow Layer
                            Positioned(
                              left: stageWidth * 0.35,
                              top: stageHeight * 0.12,
                              width: stageWidth * 0.30,
                              height: stageHeight * 0.60,
                              child: Opacity(
                                opacity: glowOpacity,
                                child: Transform.scale(
                                  scale: glowScale,
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          Color(0xB33CA0FF),
                                          Color(0x003CA0FF),
                                        ],
                                        stops: [0.0, 0.7],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // 2. Left Text "GHOST" (gh)
                            Positioned(
                              left: 0,
                              top: 0,
                              width: stageWidth * 0.42,
                              height: stageHeight * 1.0,
                              child: Opacity(
                                opacity: textOpacity.clamp(0.0, 1.0),
                                child: Transform(
                                  transform: Matrix4.diagonal3Values(
                                    textScale,
                                    textScale,
                                    1.0,
                                  ),
                                  alignment: Alignment.centerRight,
                                  child: Image.asset(
                                    'assets/images/intro_gh.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),

                            // 3. Right Text/Logo "GHOST" (st)
                            Positioned(
                              left: stageWidth * 0.6269,
                              top: 0,
                              width: stageWidth * 0.3731,
                              height: stageHeight * 1.0,
                              child: Opacity(
                                opacity: textOpacity.clamp(0.0, 1.0),
                                child: Transform(
                                  transform: Matrix4.diagonal3Values(
                                    textScale,
                                    textScale,
                                    1.0,
                                  ),
                                  alignment: Alignment.centerLeft,
                                  child: Image.asset(
                                    'assets/images/intro_st.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),

                            // 4. GAMING Text (gm)
                            Positioned(
                              left: stageWidth * 0.2125,
                              top: stageHeight * 0.7115,
                              width: stageWidth * 0.5969,
                              height: stageHeight * 0.2885,
                              child: Opacity(
                                opacity: gmOpacity.clamp(0.0, 1.0),
                                child: Transform(
                                  transform: Matrix4.diagonal3Values(
                                    gmScaleX,
                                    gmScaleY,
                                    1.0,
                                  ),
                                  alignment: Alignment.topCenter,
                                  child: Image.asset(
                                    'assets/images/intro_gm.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),

                            // 5. Skull (sk)
                            Positioned(
                              left: stageWidth * 0.4175,
                              top: stageHeight * 0.1607,
                              width: stageWidth * 0.2125,
                              height: stageHeight * 0.5632,
                              child: Transform.translate(
                                offset: Offset(skullRollX, 0),
                                child: Transform.rotate(
                                  angle: skullRollRot + shakeRot,
                                  child: Transform.scale(
                                    scale: shakeScale,
                                    child: Image.asset(
                                      'assets/images/intro_sk.png',
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
