# Architecture Decision Records (ADR) — GhostGaming

## 1. ADR-001: Retain Provider & ViewModels
- **Status**: Accepted
- **Context**: The project already uses `provider` with feature ViewModels.
- **Decision**: Keep this pattern to avoid unnecessary refactoring and maintain stability.

## 2. ADR-002: PostgreSQL RPC Functions for Business Logic
- **Status**: Accepted
- **Context**: Complex venue management, inventory deduction, and session state machine require atomic transactions.
- **Decision**: Encapsulate core mutations in PostgreSQL PL/pgSQL RPC functions with operation ID idempotency.
