# CapHive Agents Roadmap Brainstorming

This document outlines a potential roadmap for developing agents on the CapHive platform.

## Caphive Agents Roadmap

The following grid maps the 4 Agent Types against the 8 Business Domains.

| Domain | Compliance Agent 🛡️ | Ops Agent ⚙️ | Analysis Agent 📊 | Assistant Agent 💬 |
| :--- | :--- | :--- | :--- | :--- |
| **Portfolio Investments**<br>*(Active/Closed)* | • Strategy/Concentration Checks<br>• ESG Compliance<br>• Conflict of Interest | • Deal Doc Ingestion<br>• Status Updates<br>• Cash Reconciliation | • Real-time IRR/MOIC<br>• Benchmarking<br>• Scenario Modeling | • "Summarize deal update"<br>• "List Fintech deals"<br>• Investment Memo Drafts |
| **Investment Opportunities**<br>*(Pipeline/Pre-Close)* | • NDA Management<br>• Restricted List Checks<br>• Pre-Deal Conflict Checks | • DD Checklist Mgmt<br>• Data Room Ingestion<br>• IC Memo Prep Support | • Deal Screening/Scoring<br>• Pipeline Velocity<br>• Sector Heatmaps | • "Summarize Pitch Deck"<br>• "Compare Startup A vs B"<br>• "Draft IC Memo" |
| **Fund Raising / Deals** | • Jurisdiction/Marketing Checks<br>• Suitability/Appropriateness<br>• Teaser/NDA Compliance | • VDR Access Mgmt<br>• Log Soft Circles/IOs<br>• Roadshow Logistics | • Demand/Funnel Analysis<br>• Fund Size Prediction<br>• LP Conversion Rates | • "Draft LP Follow-up"<br>• "Who accessed VDR?"<br>• "Summarize Roadshow Feedback" |
| **Onboarding**<br>*(formerly KYC)* | • KYC/AML/Watchlist Checks<br>• Tax Form Validation (W8/W9)<br>• Accreditation Verification | • Sub Doc Parsing<br>• Countersignature Workflow<br>• Portal Invites | • Time-to-Close Metrics<br>• Funnel Drop-off Analysis<br>• Risk Scoring | • "Status of Investor X?"<br>• "Draft Missing Doc Email"<br>• "Explain Sub Doc Error" |
| **Commitments** | • Fund Cap Verification<br>• Side Letter Logging<br>• ERISA/BHCA Checks | • Final Closing Logs<br>• Transfer/Secondary Flows<br>• Ledger Updates | • Dry Powder Tracking<br>• Concentration Analysis<br>• Vintage Diversification | • "Show LP Total Comm."<br>• "List Side Letter LPs"<br>• "Available Dry Powder?" |
| **Calls (Capital Calls)** | • LPA/Drawdown Limits<br>• Interest Equalization<br>• ILPA Standards | • PDF Notice Generation<br>• Wire Matching<br>• Payment Chasers | • Cashflow Forecasting<br>• LP Payment Scoring<br>• Timing Optimization | • "Draft Cover Letter"<br>• "Who hasn't paid?"<br>• Calculation Explanations |
| **Distributions** | • Waterfall Validation<br>• Tax/Withholding Checks<br>• Reg. Notice Checks | • Notice & Tax Doc Gen<br>• Batch Payment Files<br>• Re-invest Handling | • DPI Trend Analysis<br>• Carry Payout Scenarios<br>• Tax Impact Est. | • "Last Dist Date?"<br>• "Explain Recallable Cap"<br>• "Total Carry Paid?" |
| **Portfolio Companies** | • Covenant Monitoring<br>• Board Rights Tracking<br>• Info Rights Checks | • KPI Collection (Form Sending)<br>• Fin. Stmt Ingestion<br>• Meeting Scheduling | • Cross-Port. Perf (Rev/EBITDA)<br>• Valuation Models (DCF)<br>• Underperf. Alerts | • "Who is CEO of X?"<br>• "Compare Rev Growth"<br>• Summarize Board Decks |

> **Note:** An agent is considered "defined" only if the following **Agent Card** is fully specified for that agent within its grid cell context:
>
> **Agent Card Schema:**
> 1.  **Customer Pain Point:** What problem are we solving?
> 2.  **Outcome:** What is the tangible result?
> 3.  **Revenue Potential:** High/Medium/Low?
> 4.  **Complexity Score:** 1-5?
> 5.  **Set of Tools:** Which tools from the toolset are required?
> 6.  **Set of Triggers:** How is it activated (Manual, Event, etc.)?
> 7.  **UX:** What are the output wireframe/xlsx mock, error states, and notifications?

---

## Agent Triggers

Agents are not always active; they operate based on specific triggers that initiate their workflows.

### 1. 👆 Manual Trigger
*   **Definition:** A user explicitly clicks a button or invokes an action from the UI.
*   **Examples:**
    *   Clicking "Run Compliance Check" on a new Deal.
    *   Clicking "Generate Capital Call Notices" in the Calls module.
    *   Manually uploading a document and selecting "Extract Data".

### 2. ⚡ Event-Based Trigger
*   **Definition:** The agent reacts automatically to a change in the system state or data.
*   **Examples:**
    *   **New Document:** A "Subscription Agreement" is uploaded -> *Trigger Ops Agent to parse.*
    *   **Status Change:** An Investment moves to "Signed" -> *Trigger Compliance Agent to check final concentration limits.*
    *   **External Data:** A bank feed transaction arrives -> *Trigger Ops Agent to match wire to Call.*
    *   **Expiration:** A Passport expiry date passes -> *Trigger Compliance Agent to flag.*

### 3. ⏰ Periodic Trigger
*   **Definition:** The agent runs on a set schedule (Cron job).
*   **Examples:**
    *   **Daily:** Check for new sanctions/watchlist matches against the LP base.
    *   **Weekly:** Send a "Missing Documents" digest email to the Ops team.
    *   **Quarterly:** Auto-generate draft Valuation Reports for all Portfolio Companies.
    *   **End of Month:** Reconcile cash ledgers against bank statements.

### 4. 🎙️ Voice / Chat Trigger
*   **Definition:** The user interacts with the agent via natural language (Text or Voice).
*   **Examples:**
    *   "Hey CapHive, draft an email to Investor X regarding their overdue call."
    *   "Summarize the performance of our Fintech portfolio."
    *   "What is the current IRR for Fund III?"

---

## Agent Toolset

To perform their tasks, agents have access to a specific set of tools and data sources.

### 1. 🗄️ Structured Data Access (RBAC)
*   **Description:** Direct access to the core database records.
*   **Key Feature:** **Access Controlled.** Agents inherently respect the permissions of the user or context they are running in.
*   **Scope:**
    *   Funds & Entities
    *   Commitments & Cap Tables
    *   Onboarding/KYC statuses
    *   Ledger Entries

### 2. 📄 Document Access
*   **Description:** Capability to read, parse, and analyze unstructured files stored in the system.
*   **Scope:**
    *   Legal Agreements (LPAs, Side Letters, SPAs)
    *   Investor KYC Docs (Passports, Utility Bills)
    *   Financial Statements (PDFs, Excel)
    *   Board Decks

### 3. 🧠 RAG / Knowledge Graph
*   **Description:** A retrieval engine that allows agents to query unstructured knowledge and relationships.
*   **Use Cases:**
    *   "What is the Management Fee defined in the Fund III LPA?"
    *   "Find all clauses related to 'Key Person' events across all active funds."
    *   Connecting a Board Deck insight to a Portfolio Company record.

### 4. 📐 Statistical Library
*   **Description:** Standard computational libraries for general data analysis and forecasting.
*   **Capabilities:**
    *   Regression analysis (for forecasting capital needs).
    *   Probability distributions (for risk modeling).
    *   Basic aggregation and trend analysis.

### 5. 🧮 Custom CapHive Tools
*   **Description:** Specialized financial engines built specifically for the Private Equity/VC domain within CapHive.
*   **Capabilities:**
    *   **IRR Engine:** XIRR calculation handling irregular cash flows.
    *   **Waterfall Calculator:** Complex distribution logic (Hurdle, Catch-up, Carry).
    *   **Equalization Engine:** Calculating interest adjustments for subsequent closings.
    *   **TVPI / MOIC Calculator.**

### 6. 📉 Graphing Tools
*   **Description:** Capability to generate visual charts and plots for reports or UI display.
*   **Capabilities:**
    *   Generating J-Curve plots for Fund Performance.
    *   Bar charts for Portfolio Company Revenue vs EBITDA.
    *   Pie charts for Sector/Geography allocation.

### 7. 📧 Email / Communication Tools
*   **Description:** Integration with communication providers to send outbound messages and read inbound replies.
*   **Capabilities:**
    *   **Drafting:** Creating context-aware email drafts for user review.
    *   **Sending:** Automated sending of notices (Capital Calls, Distribution Notices).
    *   **Reading:** Parsing inbound emails (e.g., from LPs) to trigger workflows or extract attachments.
