# Database & Transaction Model — GhostGaming

## 1. Overview
Analyzes PostgreSQL transaction boundaries, locking mechanisms, and idempotency guarantees.

## 2. Key Mechanisms
- **`SECURITY DEFINER` Hardening**: Functions execute with creator privileges but enforce `SET search_path = public` and validate `auth.uid()` and staff/customer membership.
- **Row Locking (`FOR UPDATE`)**: Prevents race conditions during session updates and post reservations.
- **Idempotency Framework (`app.begin_op` / `app.end_op`)**: Tracks operation UUIDs (`p_op`) in `operation_log` table to ensure safe network retries without duplication.

## 3. Associated Files
- PostgreSQL migration scripts (`.sql`) in project root.
