# Session Lifecycle — GhostGaming

## 1. Overview
Defines the state machine, duration calculations, game modes, and transitions for gaming sessions.

## 2. States & Transitions
- **`active`**: Session is ongoing, timer/counter is ticking.
- **`paused`**: Session is temporarily paused (pauses time calculation, records `paused_at`).
- **`waiting_payment`**: Session has ended, awaiting checkout and payment resolution.
- **`completed` / `cancelled`**: Final states.

## 3. Game Modes
- **`match_based`**: Billed and tracked by match count (e.g., FIFA matches). Uses `effective_match_seconds` or custom pricing tiers.
- **`time_based`**: Billed and tracked by duration in minutes.
- **`custom`**: Flexible hybrid billing.

## 4. Associated Files
- `20260101000003_sessions.sql`
- `20260101000029_fix_match_duration_calculation.sql`

## 5. Concurrency & Locking
- Uses `app._lock_session(p_session)` and `FOR UPDATE` in PL/pgSQL to prevent simultaneous modifications.
