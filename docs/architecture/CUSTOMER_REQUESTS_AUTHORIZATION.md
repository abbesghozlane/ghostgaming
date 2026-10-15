# Customer Requests & Authorization — GhostGaming

## 1. Overview
Details the asynchronous customer request workflow (`session_requests`) and role-based authorization model.

## 2. Request Matrix (`session_requests`)
| Request Type | Creator | Viewer | Approver / Rejecter | Associated RPC |
| :--- | :--- | :--- | :--- | :--- |
| `match` | Customer / Staff | Staff / Customer | Staff (`is_staff`) | `create_request` → `decide_request` |
| `time` | Customer / Staff | Staff / Customer | Staff (`is_staff`) | `create_request` → `decide_request` |
| `checkout` | Customer / Staff | Staff / Customer | Staff (`is_staff`) | `create_request` → `decide_request` |
| `product` | Customer / Staff | Staff / Customer | Staff (`is_staff`) | `create_request` → `decide_request` |
| `start_session` | Customer | Staff / Customer | Staff (`is_staff`) | `request_start_session` → `decide_request` |

## 3. Authorization Rules
- Never rely on UI button hiding alone. Database RLS and PL/pgSQL RPC checks (`app.is_staff()`, `auth.uid()`) enforce security.
- Unique constraints prevent duplicate pending requests (`REQUEST_ALREADY_PENDING`).

## 4. Associated Files
- `20260101000039_customer_start_session_request.sql`
- `20260101000040_fix_all_customer_requests_and_decisions.sql`
