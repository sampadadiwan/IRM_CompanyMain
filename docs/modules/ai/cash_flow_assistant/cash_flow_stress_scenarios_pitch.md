# Cash Flow Assistant — Stress Scenarios & AI Chat

## Idea

Add an AI-powered chat panel to the Cash Flow report. Fund Managers can ask "what-if" questions in plain English and get instant answers with recalculated numbers — no Excel needed.

---

## How It Looks

The existing Cash Flow report stays exactly the same on the left. A chat panel opens on the right when needed.

```
┌────────────────────────────────┬────────────────────────────┐
│                                │                            │
│  Cash Flow Report              │  💬 Chat Assistant         │
│                                │                            │
│  Fund 1 — Surplus   ₹43L      │  FM: What if expenses      │
│  Fund 2 — Shortfall ₹-499Cr   │  go up 25%?                │
│  Fund 3 — Watch     ₹2.6L     │                            │
│  Fund 4 — BLOCKED              │  AI: Fund 3 flips from     │
│  ...                           │  Watch to Shortfall.       │
│                                │  All other funds stay       │
│                                │  stable.                   │
│                                │                            │
│                                │  FM: Generate a report     │
│                                │                            │
│                                │  AI: Here you go.          │
│                                │  [📄 Download Report]      │
│                                │                            │
└────────────────────────────────┴────────────────────────────┘
```

---

## What Can the FM Ask?

**Stress Scenarios**
- "What if expenses increase by 25% next quarter?"
- "What if the TechCo sale realization gets delayed by 90 days?"
- "What if both happen at the same time?"

**Trends**
- "How has Fund 1's runway changed over the last 3 months?"
- "Which fund has deteriorated the most?"

**Cross-Fund**
- "Which fund should I prioritize for capital call?"
- "Can we absorb a 40% expense spike across all funds?"

**Reports**
- "Generate a stress report for this scenario" → downloadable document comparing base case vs stress case, ready to share with partners

---

## Base Report vs Chat

| | Base Report | Chat |
|---|---|---|
| Purpose | Official snapshot | Exploratory what-if |
| Auto-generated | Yes (scheduled) | No (FM initiates) |
| Saved & emailed | Yes | No |
| Downloadable | Yes | Yes (stress reports on demand) |

The base report is the source of truth. Chat is a lens on top — it never changes underlying data.

---

## Historical Trends

Each report run is saved as a snapshot. The assistant can look back **3 months** and answer:

> "Our runway dropped from 120 days to 45 days — what changed?"

It compares snapshots and explains what moved — new investments, expense growth, cash changes.

---

## Configurable

- **Per-client toggle** — on/off from agent settings
- When off, report page looks exactly as today

---

## Example

```
FM:  What happens if expenses go up 30% and TechCo
     realization is delayed 90 days?

AI:  2 of 7 funds change status:
     • Syndicate 3: Watch → Shortfall
     • Test Fund II: Surplus → Watch

     Biggest risk: Syndicate 3 can't cover expenses
     beyond 45 days without the TechCo realization.

     Want me to generate a downloadable report?

FM:  Yes.

AI:  📄 Download: Stress Analysis - Expenses +30%,
     TechCo delayed 90d
```
