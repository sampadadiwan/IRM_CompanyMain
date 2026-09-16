# Cash Flow Assistant — AI Chat & Stress Scenarios

## What Is This?

An extension to the existing Cash Flow Assistant that adds a **conversational AI assistant** to the report page. Fund Managers can ask questions about their cash flow data and explore "what-if" scenarios in plain English — no spreadsheets, no manual recalculation.

---

## The Problem

Today the Cash Flow report gives a static snapshot: cash available, expenses, net position, runway. If the FM wants to explore questions like:

- *"What if our expenses jump 30% next quarter?"*
- *"What happens if the expected sale from Company X gets delayed?"*
- *"How has our cash position changed over the last 3 months?"*

...they have to pull data into Excel and do the math themselves.

---

## The Solution

A chat panel on the right side of the Cash Flow report page. The FM types a question, and the assistant responds with accurate numbers pulled directly from the report data.

```
┌───────────────────────────────┬─────────────────────────────┐
│                               │                             │
│  Cash Flow Report             │  💬 Ask about your data     │
│  (existing, unchanged)        │                             │
│                               │  FM: What if expenses go    │
│  Fund 1 — Surplus             │  up 25%?                    │
│  Fund 2 — Shortfall           │                             │
│  Fund 3 — Watch               │  Assistant: Fund 2's        │
│  ...                          │  shortfall deepens by ₹12L. │
│                               │  Fund 3 flips from Watch    │
│                               │  to Shortfall. Other funds  │
│                               │  remain healthy.            │
│                               │                             │
│                               │  [Download Stress Report]   │
│                               │                             │
└───────────────────────────────┴─────────────────────────────┘
```

---

## What Can the FM Ask?

### Stress Scenarios

| Question | What Happens |
|----------|-------------|
| *"What if expenses increase by 25%?"* | Recalculates net position and runway for all funds with inflated expenses |
| *"What if the sale realization from Company X is delayed by 60 days?"* | Removes the expected inflow from the forecast and shows the impact |
| *"What if expenses spike AND realizations are delayed?"* | Combines multiple stress factors and shows the worst case |

### Trend & History

| Question | What Happens |
|----------|-------------|
| *"How has Fund 1's runway changed over the last 3 months?"* | Shows a month-by-month comparison from past reports |
| *"Which fund has deteriorated the most?"* | Compares trends across all funds and highlights the biggest movers |

### Cross-Fund Insights

| Question | What Happens |
|----------|-------------|
| *"Which fund should I prioritize for a capital call?"* | Analyzes all funds and recommends based on urgency, runway, and shortfall size |
| *"Do I have enough cash across all funds to cover a combined 40% expense spike?"* | Portfolio-level stress analysis |

### Downloadable Reports

When the FM finds a useful scenario, they can ask:

> *"Generate a stress report for this scenario"*

The assistant produces a **downloadable report** comparing the base case vs the stress scenario — ready to share with partners or the investment committee.

---

## How It Relates to the Base Report

| | Base Report | Chat & Stress |
|---|---|---|
| **Purpose** | Official cash flow snapshot | Exploratory "what-if" analysis |
| **Generated** | Automatically on schedule | On-demand, when FM asks |
| **Saved to fund** | Yes | No |
| **Emailed** | Yes | No |
| **Downloadable** | Yes (always) | Yes (on-demand from chat) |
| **Data source** | Live calculation from account entries | Uses the base report's numbers |

The base report remains the source of truth. The chat assistant is a lens on top of it — it never changes the underlying data.

---

## Historical Comparison

Each time the Cash Flow report runs, a snapshot is saved. The chat assistant can access the **last 3 months** of snapshots, enabling questions about trends:

> *"Our runway dropped from 120 days to 45 days — what drove the change?"*

The assistant compares the snapshots and explains what moved: new investments added, expense growth, cash drawdowns, etc.

---

## Configuration

This feature is **optional and per-client**. It can be toggled on/off from the agent settings:

| Setting | Description |
|---------|-------------|
| Enable Chat | Turn the chat panel on or off for this agent |
| Historical Months | How many months of past reports the chat can reference (default: 3) |

When disabled, the report page looks exactly as it does today — no changes.

---

## BRD Stress Scenarios Covered

From the original requirements:

> *"If there is an expected realization from sale of PI, highlight that a delay in realization will lead to a shortfall"*

**Covered.** The FM can ask about delayed realizations and the assistant calculates the exact impact.

> *"In case expenses for the quarter are 25% more than the average considered, what is the impact on surplus/shortfall"*

**Covered.** The FM can ask for any percentage and get instant results across all funds.

**Additionally**, the conversational interface supports questions that weren't in the original BRD but are natural follow-ups:

- Combined stress (expenses up + realizations delayed)
- Fund-specific deep dives
- Cross-fund prioritization
- Historical trend analysis

---

## Example Interaction

```
FM:   What happens to our portfolio if expenses go up 30% and the
      TechCo realization gets delayed by 90 days?

AI:   I've run the combined stress scenario across all 7 funds:

      • 2 funds change status:
        - Syndicate 3: Watch → Shortfall (₹-4.2L)
        - Test Fund II: Surplus → Watch (62 days runway)

      • Fund 1 remains in Shortfall — shortfall deepens by ₹18L

      • Computation Fund and Syndicate 4 remain healthy

      The biggest risk is Syndicate 3. Without the TechCo realization,
      it cannot cover expenses beyond 45 days.

      Would you like me to generate a downloadable report for this scenario?

FM:   Yes, generate it.

AI:   Here's your report:
      📄 Download: Stress Analysis - Expenses +30%, TechCo delayed 90d
```
