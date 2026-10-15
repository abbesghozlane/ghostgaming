# Responsive & Desktop Design — GhostGaming

## 1. Overview
Defines design standards and layout adaptivity across mobile, tablet, and desktop screens, preserving the existing dark mode aesthetic and brand identity.

## 2. Desktop Enhancements
- **Window Management**: Uses `window_manager` to initialize desktop windows at `1366x768` minimum `900x600`.
- **Responsive Scaffolding**: Uses `ResponsiveScaffold` and multi-column grid/carousel layouts in `PostsScreen` to leverage large screens without breaking mobile/tablet usability.
- **Navigation**: Sidebar / navigation rail for desktop vs. bottom nav for mobile.

## 3. Associated Files
- `lib/app/widgets/responsive_scaffold.dart`
- `lib/features/posts/presentation/posts_screen.dart`
- `lib/main.dart`
