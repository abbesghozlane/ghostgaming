# GHOST GAMING — Master Brief (Flutter + Supabase)

You are building a production Gaming Lounge Management System. UI language: **French only** (code identifiers in English). Not a prototype.

## 0. Sources of truth (priority order)
1. This brief.
2. `supabase/migrations/*.sql` — validated database (tested: `supabase/tests/sessions_test.sql`). Extend with new migrations; never bypass its RPCs.
3. `ghost_app_demo.html` — **visual + behavioral reference**: screens, navigation, role permissions, request→approval flow.
4. `ghost_screens.html` — all static screens (splash, login, signup, home, games, booking, inventory, reports, admin).
5. Original requirements doc (50 sections) and the long Ghost Gaming spec — business details.

## 1. The design must be rebuilt NATIVELY (no WebView)
Open both HTML files in a browser first. Rebuild with real Flutter widgets, same look and behavior. Compare screenshots side by side (HTML vs Flutter) for every screen before moving on.

Design = 3 layers: **L0 background** (blurred glow blobs) · **L1 surfaces** (lighter cards, 1px hairline, top highlight, deep shadow) · **L2 cutouts** (transparent PNGs floating above cards).

| HTML | Flutter |
|---|---|
| `:root` colors | `AppColors`: bg `#090915`, s1 `#1a1a38`, s2 `#101024`, purple `#8b3ae8`, light-purple `#a855f7`, pink `#ff2d9b`, green `#10b981`, amber `#f59e0b`, red `#ef4444`, muted `#9a9bb2`, blue `#a9d4ff` |
| Inter / Orbitron | `google_fonts` → `AppTextStyles` (Orbitron only for logo/big numbers) |
| `.amb` blobs | `AmbientBackground` widget (Stack + blurred circles / RadialGradient) |
| `.surface` | `AppCard` (gradient 160°, border white 7%, shadow, radius 24) |
| `.btn` / `.sm` | `AppButton` (primary gradient purple→magenta, ghost, danger) |
| `.chip` | `PillChip` · `.bd ok/md/lo` → `StatusBadge` |
| `.feat` + `.car` + pager | `FeaturedGameCarousel`: `PageView` (snap) + animated dots (active 24×6 pink) + 4.5s autoplay paused 8s after touch |
| `.hero`, `.stat`, `.qa`, `.kpi`, `.mi` | `HeroCard`, `StatCard`, `QuickActionCard`, `KpiCard`, `MenuTile` |
| `.nav` | `BottomNavShell` (role-based tabs, locked tab shows 🔒 → "Accès refusé") |
| `data-a="…"` | ViewModel method · `data-bind` → provider field |
| image slots `<img src="">` | `AppNetworkImage` (cached) + placeholder; images come from Supabase Storage |

Build `AppTheme` + these shared widgets in M0, then screens. Never duplicate a component.

## 2. Roles & permissions (as in the demo, enforced for real)
- **Owner**: everything (postes, stock, prix, rapports, admin, jeux, réservations).
- **Employee**: postes + stock; Rapports/Admin locked; cannot edit prices.
- **Customer**: catalogue, own session, +Match / +Time requests, bookings, wallet/credit view.
Flutter hides/locks UI (UX only). **RLS + RPC checks are the security** (already in migrations). Route guards with `go_router`.

## 3. Architecture
Feature-first: `features/{auth,dashboard,posts,games,sessions,orders,inventory,payments,customers,wallet,credit,notifications,reservations,reports}/{data,domain,presentation}`.
View → ViewModel (Riverpod `Notifier`/`AsyncNotifier`) → Repository (source of truth, abstract + Supabase impl + in-memory impl) → Service (`SupabaseClient` init once). No Supabase calls in widgets. No business logic in widgets.
Start with **in-memory repositories seeded like the demo**, then swap to Supabase per phase. Pin package versions at M0 after checking pub.dev (supabase_flutter, flutter_riverpod, go_router, google_fonts, freezed, cached_network_image, fl_chart, mobile_scanner, intl).

## 4. Business rules (already implemented server-side — do not re-implement in Dart)
- **Session is the core**: Customer → Session → Post → Orders → Bill → Payment → Invoice. Standalone POS orders ≠ session orders.
- **Post state machine**: available, reserved, starting, playing, paused, waiting_payment, maintenance, offline. Derived from the open session by `_sync_post`; clients cannot write it (trigger blocks).
- **Timers**: store timestamps only (`started_at, paused_at, ended_at, total_paused_seconds, planned_duration_seconds`). UI: `remaining = planned − elapsed` from `DateTime.now()` (use server-clock offset). Never a decrementing variable.
- **Football (match-based)**: effective match time = in-game minutes × multiplier. Defaults: eFootball/PES **×1.7**, EA FC/FIFA **×1.5** (10 min → 17 / 15 min). Server computes and stores `planned_duration_seconds`; Dart `GameTimingPolicy` is for previews only; shared test vectors in `test_vectors/timing.json`.
- **Classification**: `GameClassificationService` (Dart) detects football by alias list (case/accent/whitespace-insensitive: eFootball*, PES*, EA FC*, FC 25/26, FIFA*) **once at game create/edit**, result saved in `games.game_mode` + `mode_source='auto'`. Owner override (`match_based|time_based|custom`) sets `mode_source='owner'` and always wins; auto-detect never touches it.
- **Time-based pricing**: `per_minute`, per 15/30/60 (**rounded up to whole units**), `fixed_price`. Package/promotion/membership_discount: later migration tables.
- **Requests**: customer `create_request` → staff `decide_request` (atomic: validate, add match/time, notify, audit). Session end auto-cancels pending requests.
- **Concurrency & retries**: every mutating RPC takes a client-generated `operation_id` (UUID); a retry returns the stored result. Row locks: session first, then request; posts locked in id order.
- **Wallet ≠ Credit**: separate tables + append-only ledgers (phase 6). `sum(payments) + credit = invoice total` enforced in the close RPC.
- **Stock**: decrement inside the sale transaction with `stock >= qty` check; every change = `inventory_movements` row.
- **Audit log** for price changes, session start/end, matches/time, payments, refunds, credit/wallet/stock changes, role changes.
- **Realtime**: Broadcast-from-database on **private channels** (`venue:{id}:posts|sessions|requests|catalog`, `session:{id}`, `user:{id}`), authorized by RLS on `realtime.messages`. One `RealtimeService`, subscribe/dispose in providers (never in `build()`), reconnect → **refetch snapshot** (broadcasts are not replayed). Verify current Supabase Realtime docs before implementing.
- **Errors**: RPCs raise codes (`SESSION_NOT_ACTIVE`, `POST_NOT_AVAILABLE`, `GAME_NOT_MATCH_BASED`, `FORBIDDEN`, `REQUEST_ALREADY_PENDING`…). Map to French messages in one `ErrorMapper`. Never show raw Postgres errors.
- **Time zone**: UTC in DB, `Africa/Algiers` for display, centralized. French date format (`intl`, `fr`).
- **Security**: never ship the service-role key; RLS on every table; QR token validated server-side.

## 4b. Decisions to confirm with the owner (assumptions made, change by migration)
1. PES counted in the **×1.7** family with eFootball.
2. +Time requests are refused on match-based games.
3. Whole-unit rounding for 15/30/60-minute pricing (+30 min on a per-hour game bills a full hour; use per-30 pricing to avoid).
4. Customer cannot start a session alone (staff starts); venue setting can change this later.

## 5. Phases (finish + demo + tests before the next; ask me "OK" between phases)
- **M0** Flutter project, theme, shared widgets, router + role guards, in-memory repos seeded from the demo, Splash/Login/Signup. Apply migrations to a Supabase project, wire Auth.
- **M1** Home (hero, stats, **games carousel**, quick actions), Posts, Games (images via Storage), Games manager, Inventory.
- **M2** Session engine UI on the existing RPCs: Live Floor, start, +Match/+Time, pause/resume, transfer, end, timer, timeline.
- **M3** Customer app: home, current session, requests (+Match/+Time), booking, notifications with deep links, QR post linking.
- **M4** Products/POS/orders (Pay Now vs Add to Session), inventory movements, live bill.
- **M5** Payments: cash/card/wallet/credit/split, invoices (PDF share).
- **M6** Realtime across all modules; shifts, expenses, reports + heatmap.
- **M7** Reservations, waitlist, loyalty, membership, packages, promotions.
- **M8** Offline queue (operation_id), hardening, performance, accessibility.

## 6. Quality bar (world-class standards)
- `flutter analyze` clean (strict lints, e.g. `very_good_analysis`), `dart format`, CI on every PR (analyze + tests + SQL tests).
- Tests: unit (pricing, classification, multipliers, remaining time, ledger math), repository, widget (PostCard, session screen, payment), **golden tests vs the HTML screenshots**, integration (start → +Match → product → pay → close), SQL tests (`supabase/tests`).
- Accessibility: tap targets ≥48dp, contrast, text scaling, semantics labels.
- Responsive: phones, tablets (no fixed 393px widths); loading/empty/error/retry state on every async view; skeletons.
- Privacy: minimal personal data, delete/export customer data on request (check Algerian data-protection law 18-07 with a lawyer).
- Conventional commits, small PRs, one migration per change, ADR notes for architectural decisions.

## 7. Mandatory acceptance tests (3 devices)
1. Employee starts POST 05 eFootball Match 1 → Owner sees it instantly → Employee approves +Match → Owner and Customer see Match 2 with **no refresh**.
2. Owner changes FIFA price 100 → 120 → Customer sees it live.
3. eFootball 10 min ×1.7: after 5 real minutes remaining ≈ 12 min, also after background/reopen/other device. Tekken 60 min = 60 real minutes.
4. Two staff press `End Session` and `+Match` simultaneously → exactly one wins; never a match after the end.

## 8. How you must work
Per phase: inspect → state what exists → design DB change first (migration + RLS + test) → domain → repository → ViewModel → UI from the HTML design → realtime → tests → fix → report. Don't invent features. No fake data once Supabase is wired. If you hit an architectural problem, explain Problem / Cause / Fix / Files / Migration, then apply the safest fix. Start with **M0 only**: reply with your understanding (10 lines), assumptions, and the file plan, then build.
