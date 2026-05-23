---
name: feedback-sequence-diagrams
description: Always add Mermaid sequence diagrams to technical docs when documenting new flows
metadata:
  type: feedback
---

Always add Mermaid sequence diagrams to technical documentation when describing new workflows or flows.

**Why:** User explicitly requested this — diagrams make multi-actor flows (investor, fund admin, system) immediately clear without reading prose.

**How to apply:** Any time a technical or manual QA doc is written or updated for a feature involving multiple actors or state transitions, include at least one `sequenceDiagram` block in Mermaid. Place it near the top of the relevant section, before prose description. Use Mermaid format (```mermaid) so it renders on GitHub.
