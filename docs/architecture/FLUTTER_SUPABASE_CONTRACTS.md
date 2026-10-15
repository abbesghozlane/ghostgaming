# Flutter-to-Supabase Contracts — GhostGaming

## 1. Overview
Documents the exact end-to-end execution path from Flutter Widgets through ViewModels and Repositories to Supabase RPCs and PostgreSQL.

## 2. Critical Operation Paths
### A. Starting a Session (Staff)
- **Entry Point**: `PostsScreen` / `_StartSessionDialog` → `SessionDashboardViewModel.startSession()`
- **Repository**: `SessionDashboardRepository.call('start_session', {...})`
- **RPC Name**: `public.start_session(p_op, p_post, p_game, p_customer, p_initial_minutes)`
- **Permissions**: Staff role required (`app.is_staff()`).
- **Error Mapping**: `POST_NOT_AVAILABLE`, `GAME_NOT_AVAILABLE`, `FORBIDDEN`, `UNAUTHENTICATED`.

### B. Customer Session Request (`create_request` / `request_start_session`)
- **Entry Point**: `CustomerHomeScreen` or `PostsScreen` (customer role)
- **Repository**: `CustomerRepository.createSessionRequest()` or `enqueuePostRequest()`
- **RPC Name**: `public.create_request` / `public.request_start_session`
- **Permissions**: Authenticated customer or staff.
- **Error Mapping**: `REQUEST_ALREADY_PENDING`, `SESSION_NOT_ACTIVE`, `GAME_NOT_TIME_BASED`, `GAME_NOT_MATCH_BASED`.

### C. Staff Decision on Request (`decide_request`)
- **Entry Point**: `StaffHomeScreen` (`_RequestCard`)
- **Repository**: `SessionDashboardViewModel.decideRequest()`
- **RPC Name**: `public.decide_request(p_op, p_request, p_approve)`
- **Permissions**: Staff role required (`app.is_staff()`).
- **Supported Types**: `match`, `time`, `checkout`, `start_session`, `product`.

## 3. Associated Files
- `lib/features/sessions/data/session_dashboard_repository.dart`
- `lib/features/customers/data/customer_repository.dart`
- SQL migrations (`003`, `029`, `036`, `037`, `039`, `040`).

## 4. Error Handling & Idempotency
- All mutating calls use `OperationId.create()` as `p_op` for transactional idempotency.
- Exceptions caught and formatted via user-friendly error mappers.
