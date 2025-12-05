# Architecture Overview

This document summarizes the proposed platform architecture, technology stack choices, and operational practices for development, staging, and production.

## Technology Stack

### Backend
- **Framework:** FastAPI (Python) for type-hinted, async-friendly APIs with automatic OpenAPI documentation.
- **Runtime:** Python 3.12 with uvicorn/gunicorn for HTTP serving.
- **Containerization:** Docker images built via multi-stage to keep runtime images small.

### Frontend
- **Framework:** React with Vite for fast dev server and build tooling.
- **UI Library:** Tailwind CSS for consistent styling.
- **Rendering:** CSR-first with server-side prerendering for key marketing pages as needed.

### Database
- **Primary Store:** PostgreSQL for relational data and transactional guarantees.
- **Caching:** Redis for request-level caching, rate limiting, and background job coordination.
- **Migrations:** Alembic migrations owned by the API service.

### Authentication & Authorization
- **Identity:** OpenID Connect provider (e.g., Auth0/Okta) issuing JWT access tokens.
- **Session Model:** Short-lived access tokens with refresh tokens stored in HttpOnly cookies.
- **Authorization:** Role-based claims embedded in JWT; fine-grained checks enforced in API layer.

### Payments
- **Processor:** Stripe for card processing, invoicing, and subscription management.
- **Webhook Handling:** Dedicated webhook endpoint in the API service with signature verification.
- **Idempotency:** Stripe idempotency keys for retries; persisted ledger table in PostgreSQL for reconciliation.

## Service Boundaries

### API Service
- Serves REST/JSON endpoints and authentication callbacks.
- Owns business logic, validation, and authorization checks.
- Exposes webhook endpoints for Stripe and event triggers for internal workers.

### Worker / ETL Service
- Runs asynchronous jobs (email sends, invoice finalization, data imports/exports).
- Listens to queue topics emitted by the API (e.g., via Redis streams or a message broker).
- Executes scheduled ETL tasks to move data between OLTP (PostgreSQL) and analytics storage.

### Web Frontend
- Serves the React SPA build (via CDN or edge cache).
- Performs authenticated calls to the API with bearer tokens obtained through the OIDC flow.
- Uses feature flags to gate beta features and configuration fetched from the API.

## Data Flow

### User Journey
1. Browser loads the React app from CDN/edge.
2. User authenticates via the OIDC provider; the frontend receives tokens in secure cookies.
3. Frontend calls API endpoints with access tokens; API validates JWT and enforces RBAC.
4. API reads/writes PostgreSQL and uses Redis for caching and rate limits.
5. API emits events to the queue for background processing (emails, invoices, analytics exports).
6. Worker consumes events, performs side effects, and writes results back to PostgreSQL.

### Payments
1. Frontend creates PaymentIntent via API; API forwards to Stripe with idempotency keys.
2. Stripe sends webhooks to API; webhook handler verifies signatures and records events.
3. Worker reconciles payments by comparing Stripe events with the ledger table and updates subscriptions.

### Data Diagram (simplified)
```
[React Frontend] --HTTPS+OIDC--> [API Service] --SQL--> [PostgreSQL]
        |                                |\
        |                                | \--cache/rate--> [Redis]
        |                                |\
        |                                | \--events--> [Queue/Streams]
        |                                           \
        |                                            \---> [Worker / ETL] --SQL--> [PostgreSQL]
        |                                                                              \
        |                                                                               \--exports--> [Analytics/BI]
```

## Environment Strategy

### Environments
- **Development:** Local Docker Compose with hot reload for API and frontend; seeded PostgreSQL/Redis; uses sandbox Stripe and OIDC tenants.
- **Staging:** Mirrors production topology with smaller footprints; auto-deploy from main; runs integration and smoke tests; uses sandbox Stripe and staging OIDC tenants.
- **Production:** Highly available deployments with autoscaling; uses managed PostgreSQL/Redis; real Stripe account and production OIDC tenant.

### Secrets Management
- **Source of Truth:** Centralized secrets store (e.g., HashiCorp Vault or cloud KMS/Secrets Manager).
- **Access:** CI/CD retrieves environment-specific secrets and injects them as environment variables at deploy time.
- **Rotation:** Periodic rotation with short TTL tokens; service accounts scoped per environment.
- **Local Dev:** `.env` files generated from the secrets store with restricted permissions; no secrets checked into VCS.

### Observability & Operations
- **Logging:** Structured JSON logs shipped to centralized logging (e.g., ELK or Cloud Logging).
- **Metrics/Tracing:** OpenTelemetry instrumented across services; exported to Prometheus + Grafana or cloud APM.
- **Alerts:** SLO-based alerting for latency, error rates, and payment failures.

