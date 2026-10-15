# Phase 3A Validation Report — GhostGaming

## 1. Scenarios Verified
We inspected the execution paths for the following core operations across Dart and SQL files without modifying any code or database:
- `start_session`: Staff starting a session on a post.
- `request_start_session`: Customer requesting to start a session on a post.
- `create_request`: Customer/staff creating session requests (`match`, `time`, `checkout`, `product`).
- `decide_request`: Staff approving or rejecting pending session requests.
- `customer_add_product_to_session`: Direct or requested product orders during active sessions.

---

## 2. Operation Traceability Matrix

| Operation | UI Entry Point | ViewModel / Controller | Repository Method | Supabase RPC | PostgreSQL Function & Guards |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Start Session** | `PostsScreen` (`_StartSessionDialog`) | `SessionDashboardViewModel.startSession()` | `SessionDashboardRepository.call()` | `rpc('start_session', ...)` | `public.start_session()` (`app.is_staff()`, `FOR UPDATE`, `app.begin_op`) |
| **Request Start Session** | `PostsScreen` (`_CustomerStartSessionDialog`) | `PostsScreen` / Direct Repo call | `CustomerRepository.enqueuePostRequest()` | `rpc('request_start_session', ...)` | `public.request_start_session()` (`auth.uid()`, `venue_id`) |
| **Create Request** | `PostsScreen` (`_sessionAction`) / `CustomerHomeScreen` | `CustomerHomeScreen` / Direct Repo call | `CustomerRepository.createSessionRequest()` | `rpc('create_request', ...)` | `public.create_request()` (`app._lock_session()`, `venue_members` check) |
| **Decide Request** | `StaffHomeScreen` (`_RequestCard`) | `SessionDashboardViewModel.decideRequest()` | `SessionDashboardRepository.call()` | `rpc('decide_request', ...)` | `public.decide_request()` (`app.is_staff()`, `FOR UPDATE`, routing by `req.type`) |
| **Add Product** | `PostsScreen` (`_addProductToSession`) | `SessionDashboardViewModel` / Local Repo | `CustomerRepository.addProductToSession()` | `rpc('customer_add_product_to_session', ...)` | `public.customer_add_product_to_session()` (checks session ownership or staff) |

---

## 3. Confirmed Errors & Vulnerabilities (Evidence-Based)
1. **Request Type Mismatches in `decide_request` (Recently Patched in Mig 040)**:
   - *Evidence*: `20260101000037` introduced `product` requests, but previous `decide_request` lacked a `product` handler, resulting in `REQUEST_TYPE_NOT_SUPPORTED`. Migration `040` successfully resolved this.
2. **Game Mode Compatibility in `create_request` & `decide_request`**:
   - *Evidence*: Time requests on match-based games threw `GAME_NOT_TIME_BASED`. Migration `040` added intelligent routing in `decide_request` to handle time requests on match-based games.
3. **Error String Propagation**:
   - *Evidence*: `posts_screen.dart` previously caught exceptions and printed raw `PostgrestException` messages. Patched via `_formatRequestError()`.

---

## 4. Documentation vs. Implementation Discrepancies
- **Discrepancy**: Earlier documentation did not fully map out the newly introduced `product` and `pause_requested` payloads in `create_request` and `decide_request`.
- **Resolution**: Mapped in Phase 2 architectural docs (`FLUTTER_SUPABASE_CONTRACTS.md`, `CUSTOMER_REQUESTS_AUTHORIZATION.md`).

---

## 5. Test Gaps
- Existing tests cover timing policies (`game_timing_policy_test.dart`) and offline queue (`offline_operation_queue_test.dart`), but lack end-to-end integration tests verifying `decide_request` approval routing for `product`, `match`, and `time` request types.

---

## 6. Prioritized Risks
1. **Risk 1 (Medium)**: Realtime sync lag between customer request creation and staff notification display.
2. **Risk 2 (Low)**: Handling offline request creation when offline operation queue replays mutations upon reconnection.

---

## 7. Small Fix Plan & Verification Tests
- No immediate fixes required at this stage as Phase 3A is strictly validation. Future test additions will target integration test coverage for `decide_request`.
