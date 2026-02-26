---
name: technical-feature-doc-expert
description: Creates deep technical documentation for specific features. Analyzes codebase to identify all entry points, usages, side effects, and outcomes. Ideal for documenting complex logic, data flows, and architectural dependencies.
---

# Technical Feature Documentation Expert

This skill enables the agent to produce high-quality, deep technical documentation by tracing a feature's implementation across the modular Rails (Packs) architecture.

## Documentation Workflow

### 1. Discovery & Deep Analysis
To document a feature technically, perform a comprehensive search across the codebase:
- **Entry Points**: Identify how the feature is triggered (Controllers, API endpoints, Sidekiq Jobs, Rake tasks, or Stimulus controllers).
- **Core Logic**: Locate the primary business logic, usually in `app/packs/[domain]/[sub_domain]/services/` or `Trailblazer::Operation` classes.
- **Data Model & Persistence**: Analyze relevant models, migrations, and database schema changes. Look for `ActiveRecord` callbacks and `Audited` configurations.
- **Usages & Dependencies**: Use `grep` or `rg` to find all places where the feature's classes or methods are invoked. Check for internal dependencies between packs.
- **Outcomes & Side Effects**:
    - **Data changes**: What records are created, updated, or soft-deleted (`Paranoia`)?
    - **Events/Notifications**: Does it trigger `Noticed` notifications or `ActiveSupport::Notifications`?
    - **Background Tasks**: Are any `Sidekiq` jobs enqueued?
    - **Search Indexes**: Does it trigger `Chewy` (Elasticsearch) index updates?
    - **External Integrations**: Does it call external APIs (e.g., AWS S3 via Shrine, email services)?

### 2. Technical Document Structure
Technical documentation should follow this structure:

- **# [Feature Name] Technical Documentation**
- **## 🏗️ Architecture Overview**: High-level description of the feature's role in the system and the packs involved.
- **## 🛠️ Implementation Details**:
    - **Key Classes & Methods**: List the main components and their responsibilities.
    - **Data Flow**: Explain how data moves through the system (use Mermaid diagrams if possible).
- **## 🔗 Entry Points & Usages**:
    - Detailed list of where this feature is exposed (UI, API, CLI).
    - Map of internal calls from other parts of the application.
- **## ⚡ Outcomes & Side Effects**:
    - **Synchronous**: Immediate database updates, state changes.
    - **Asynchronous**: Background jobs, scheduled tasks.
    - **External**: Third-party API interactions.
- **## 🧪 Testing Strategy**:
    - Overview of existing tests (RSpec, Cucumber, Playwright).
    - Areas requiring special attention during testing.
- **## ⚠️ Constraints & Edge Cases**: Known limitations or specific conditions where the feature behaves differently.

### 3. Writing Guidelines
- **Perspective**: Write for developers and technical stakeholders.
- **Precision**: Use exact class names, method names, and file paths.
- **Visuals**: Use code blocks for snippets and Mermaid for diagrams.
- **Context**: Link related technical docs or ADRs (Architecture Decision Records) if they exist.

## Example Usage

### Commands
- `/skill:technical-feature-doc-expert document the 'Investor Onboarding' flow from a technical perspective`
- `/skill:technical-feature-doc-expert analyze the side-effects of 'Capital Call' generation`

### Prompting the Agent
"Using the technical-feature-doc-expert skill, perform a deep dive into the `Subscription` feature in `app/packs/investors`. Map out all its usages across the app, explain the state machine transitions, and list every side effect including background jobs and notifications."
