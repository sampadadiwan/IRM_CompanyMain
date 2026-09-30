# [Feature Name] — Proposal

> **Audience:** Business team, product, QA, support — non-technical.
> **Companion document:** [Design](design.md)

> **Planning phase — no code changes.** This document proposes and explains the change. Do not
> edit application code while writing it; implementation happens later, in the tasks phase.

---

## Why

<!-- 1-2 sentences: what problem does this solve, or what opportunity does it capture? Why now?
     How does it work today (if anything)? -->

## What Changes

<!-- What changes for the user/business, in plain language. If the feature introduces a new
     mental model, explain it with a simple analogy. Bullet the concrete changes; mark breaking
     changes with **BREAKING**. -->

### Flow Diagram

<!-- Show the current flow ("Before") and the new flow ("After") as mermaid flowcharts, not
     ASCII art. One Before + After pair per flow the change alters, each with a one-line caption.
     Use plain-English node labels (no class names), a diamond for each decision, and colour the
     manual steps being removed (red) and the new steps (green) so the difference is visible at a
     glance. Lint with the mermaid command from the design instruction.
     Example:
     ```mermaid
     flowchart LR
         A["User does X"] --> B["Retypes it by hand"] --> C["Result"]
         classDef manual fill:#fdecea,stroke:#c62828,color:#000
         class B manual
     ```
-->

---

## User Stories

### US-1: [Title]

**As a** [role],
**I want** [goal],
**So that** [benefit].

**Acceptance criteria:**
- <!-- Specific, testable criteria -->
- <!-- Be precise about UI elements, messages, behavior -->

<!-- Add more user stories as needed. Cover main flow AND edge cases. -->

---

## UI Behavior

### [Screen/Entry Point Name]

<!-- ASCII art mockup of the UI with realistic data -->

```
┌─────────────────────────────────────────────────────┐
│  [Screen Title]                                   ✕  │
│                                                     │
│  <!-- UI elements here -->                          │
│                                                     │
└─────────────────────────────────────────────────────┘
```

**Behavior notes:**
- <!-- Toggle behavior, conditional visibility, button states -->
- <!-- Turbo Frame updates, no-reload behavior -->

<!-- Add more screens as needed -->

---

## What This Feature Does NOT Cover

| Excluded | Covered In |
|---|---|
| <!-- Item --> | <!-- Module/Phase --> |

---

## Validation Rules

| Field | Rule | Default |
|---|---|---|
| <!-- field --> | <!-- rule --> | <!-- default --> |

---

## Behavior Rules

| Scenario | What User Sees |
|---|---|
| <!-- scenario --> | <!-- result --> |

---

## Resolved Design Decisions

| # | Decision | Resolution |
|---|---|---|
| 1 | <!-- question --> | <!-- resolution --> |

---

## Capabilities

### New Capabilities

<!-- Capabilities being introduced. Each creates specs/<capability-path>/spec.md. -->
- `<capability-path>`: <brief description>

### Modified Capabilities

<!-- Existing capabilities whose REQUIREMENTS are changing. Leave empty if none. -->

---

## Impact

<!-- Affected code, APIs, dependencies, systems -->

---

## Benefits

1. <!-- Concrete benefit for the end user -->

---

## FAQ

<!-- Anticipate the questions business/product/QA/support will ask. One Q&A per row.
     Keep answers non-technical — link to design.md for "how". -->

| Question | Answer |
|---|---|
| <!-- e.g. Who can use this? --> | <!-- answer --> |
| <!-- e.g. What happens to existing data? --> | <!-- answer --> |
| <!-- e.g. Does this change pricing/billing/notifications? --> | <!-- answer --> |

---

## Design Principle for the Next Phase

<!-- Reminder carried into design.md: keep the design DRY and simple. Prefer reusing existing
     services, components, and patterns over introducing new abstractions. Flag here anything in
     this proposal that risks a complex design, so the design phase can address it head-on. -->
