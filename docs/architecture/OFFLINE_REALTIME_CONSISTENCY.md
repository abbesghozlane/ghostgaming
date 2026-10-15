# Offline & Realtime Consistency — GhostGaming

## 1. Overview
Outlines offline resilience, Hive local caching, `OfflineOperationQueue`, and Supabase Realtime channel subscriptions.

## 2. Strategies
- **Offline Queue**: Mutations are queued locally when offline and replayed upon reconnection.
- **Realtime Subscriptions**: Channels listening on `venue:$venueId:sessions` and `venue:$venueId:requests` automatically refresh ViewModels upon database changes.
- **Optimistic UI vs. Server Truth**: Local states are reconciled with server responses via repository refresh calls.

## 3. Associated Files
- `lib/core/offline/offline_operation_queue.dart`
- `lib/features/sessions/data/session_dashboard_repository.dart`
