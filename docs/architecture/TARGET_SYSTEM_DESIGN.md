# Target System Design — GhostGaming

## 1. Goal and Scope
This document defines the high-level target architectural blueprint for the GhostGaming venue management system. It establishes boundaries, responsibilities, and architectural patterns across Flutter UI, Provider/ViewModels, Repositories, Supabase PostgREST client, and PostgreSQL PL/pgSQL RPC functions.

## 2. Current State vs. Target State
- **Current State**: Modular feature folders in Flutter (`lib/features/`), GoRouter navigation with role-based redirection, Provider + ViewModels, Supabase client repositories, and PostgreSQL database migrations with PL/pgSQL RPCs.
- **Target State**: Clean, robust contracts between layers, strict error typing and mapping, unified offline/online synchronization guarantees, and responsive desktop layout adaptivity without altering the visual identity or core business rules.

## 3. Architecture Layers
1. **Presentation Layer (Flutter Widgets & Screens)**: Declarative UI, responsive layouts for mobile, tablet, and desktop (using `window_manager` and `ResponsiveScaffold`).
2. **State Management & Coordination (Provider & ViewModels)**: `ChangeNotifier` / ViewModels managing UI state, loading states, and error handling.
3. **Data & Repository Layer (Repositories)**: Abstraction over Supabase client, local Hive storage, and `OfflineOperationQueue`.
4. **API & RPC Layer (Supabase / PostgREST)**: Secure RPC execution with operation IDs (`p_op`) and JWT claims.
5. **Database Layer (PostgreSQL)**: ACID-compliant tables, Row-Level Security (RLS), and atomic PL/pgSQL functions (`SECURITY DEFINER`, `FOR UPDATE`).

## 4. Associated Files
- `lib/main.dart`
- `lib/app/router/app_router.dart`
- `lib/features/`

## 5. Architectural Decisions & Alternatives
- **Decision**: Keep Provider + ViewModel + Repository pattern as established in the project.
- **Alternative**: Adopting Bloc or Riverpod (rejected to avoid unnecessary rewrites and preserve team velocity).

## 6. Testing & Quality Gates
- Widget tests for screens, unit tests for ViewModels, repository tests for error mapping, and database integration tests.

## 7. Unknowns / Needs Verification
- Full offline capability matrix for financial transactions.
