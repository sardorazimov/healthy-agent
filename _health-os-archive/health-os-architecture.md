# AI Health Operating System Architecture

## Product Surface

Miransas Health OS turns the current local agent into the edge component of a health operating system. The production system should be split into:

- Local agent: device telemetry, reminders, HUD, privacy-preserving local cache.
- API service: authenticated user profiles, health timeline, goals, memories, reports, RAG, and agent orchestration.
- Data service: relational store for canonical records, vector index for retrieval, object storage for generated PDFs.
- Integrations service: Apple Health and Google Fit sync workers with explicit consent and revocation.
- UI: dashboard, timeline, goals, agent workspaces, reports, integrations, and safety disclosures.

## Folder Structure

- `include/health_os`: public domain contracts for reusable services.
- `src/health_os`: reusable C service implementation that can be embedded by the local agent.
- `migrations`: relational schema for production storage.
- `tests`: focused unit tests for domain behavior.
- `docs`: architecture, integration, and safety notes.
- `ui`: static prototype components for the modern dashboard surface.

## Core Services

- Profile service owns demographics, preferences, consent, and personalization context.
- Memory service extracts durable preferences and recurring patterns from timeline events.
- Timeline service stores immutable health events from manual entry, agents, and integrations.
- Goal service tracks active, paused, and completed goals with normalized progress.
- Score service calculates an explainable health score from nutrition, sleep, fitness, and safety signals.
- RAG service retrieves vetted knowledge documents and long-term memories before agent generation.
- Agent service routes to nutrition, sleep, and fitness agents with shared guardrails.
- Reminder service schedules local or remote nudges and records delivery.
- Report service builds weekly summaries and PDF artifacts.
- Safety service blocks urgent medical scenarios and constrains general medical advice.

## RAG Flow

1. Normalize the user request and classify intent.
2. Run medical safety checks before retrieval.
3. Retrieve user memories, recent timeline events, active goals, and curated knowledge documents.
4. Generate an agent response with citations and explicit uncertainty.
5. Run output safety checks.
6. Persist the interaction and any durable memory candidates.

## Medical Guardrails

The system is wellness support, not diagnosis or emergency care. It must:

- Block urgent symptoms such as chest pain, breathing difficulty, overdose, stroke symptoms, and self-harm.
- Defer diagnosis, prescribing, medication changes, and dosage decisions to licensed clinicians.
- Show emergency guidance for blocked inputs.
- Log safety events for audit and quality review.
- Keep agent recommendations general, habit-oriented, and citation-backed.

## Weekly PDF Reports

Reports should include:

- Health score and explanation.
- Nutrition, sleep, and fitness trend summaries.
- Goal progress and missed reminders.
- Notable timeline events and integration highlights.
- Safety disclaimers and escalation guidance.

The local C foundation defines the report inputs; a production API can render PDFs with a server-side HTML-to-PDF engine and store paths in `weekly_reports`.

## Apple Health Architecture

Apple Health data is available through HealthKit on iOS/watchOS, not directly through a plain macOS command-line agent. The production architecture should use:

- iOS companion app with HealthKit entitlements.
- Explicit read permissions per data type.
- On-device normalization into timeline events.
- Encrypted sync to the API service.
- Cursor-based incremental sync stored in `integration_sync_cursors`.
- Revocation support that disables sync and optionally deletes provider data.

Initial data types: steps, active energy, workouts, sleep analysis, heart rate, resting heart rate, weight, mindful minutes.

## Google Fit Architecture

Google Fit sync should use OAuth through a backend integration service:

- Request least-privilege scopes.
- Store refresh tokens in a secret manager, referenced by `token_ref`.
- Pull changes on a schedule and normalize to timeline events.
- Keep provider-specific IDs in metadata for idempotency.
- Support user revocation and cursor reset.

Initial data types: steps, workouts, calories, sleep sessions where available, heart rate, weight.
