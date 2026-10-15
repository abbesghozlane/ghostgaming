# Module Contracts — GhostGaming

## 1. Overview
Defines module boundaries, responsibilities, dependencies, and data ownership across all 22 feature modules in `lib/features/`.

## 2. Core Modules
### Dashboard & Sessions (`dashboard`, `sessions`, `posts`)
- **Responsibility**: Active venue posts management, session lifecycle (start, pause, resume, end), timer countdowns, and real-time session events.
- **Data Owned**: `sessions`, `session_events`, `session_requests`, `posts`.
- **Dependencies**: `games`, `customers`, `inventory`.
- **RPCs Called**: `start_session`, `pause_session`, `resume_session`, `end_session`, `create_request`, `decide_request`, `customer_add_product_to_session`.
- **Permissions**: Staff (`owner`, `manager`, `employee`) for management; customer (`customer`) for post reservation requests and session interaction actions.

### Customers & Authentication (`auth`, `customers`)
- **Responsibility**: User authentication, venue membership, customer wallet credits, loyalty points, and customer home dashboard.
- **Data Owned**: `customers`, `venue_members`, `users`.
- **Dependencies**: `sessions`, `promotions`.
- **Permissions**: Role-based access control (`owner`, `manager`, `employee`, `customer`).

### Inventory & Games (`inventory`, `games`)
- **Responsibility**: Product catalog, stock quantities, pricing tiers, game modes (`match_based`, `time_based`).
- **Data Owned**: `products`, `games`, `post_games`, `inventory_movements`.
- **Dependencies**: None.
- **Permissions**: Staff management.

## 3. Associated Files
- `lib/features/sessions/`
- `lib/features/posts/`
- `lib/features/customers/`
- `lib/features/dashboard/`

## 4. Risks & Mitigations
- *Risk*: Direct cross-module coupling.
- *Mitigation*: Enforce repository and RPC encapsulation.
