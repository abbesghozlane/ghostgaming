# Error Handling Standard — GhostGaming

## 1. Overview
Defines a unified error handling and message translation strategy across Flutter and Supabase.

## 2. Error Categorization & Translation
- **Business Rule / Validation (`REQUEST_ALREADY_PENDING`, `SESSION_NOT_ACTIVE`, `GAME_NOT_TIME_BASED`)**: Translated via `_formatRequestError()` and repository error mappers into user-friendly French/Arabic messages.
- **Authorization (`FORBIDDEN`, `42501`)**: Translated to "Votre rôle ne permet pas d'effectuer cette opération."
- **Network / Socket**: Handled gracefully with offline queue fallback.
- **Internal / Unexpected**: Logged securely via `debugPrint` without exposing database internals to the user interface.

## 3. Associated Files
- `posts_screen.dart` (`_formatRequestError`)
- `session_dashboard_repository.dart` (`_friendlyError`)
- `customer_home_screen.dart` (`_friendlyError`)
