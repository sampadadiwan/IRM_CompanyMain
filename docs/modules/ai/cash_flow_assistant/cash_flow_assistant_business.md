# Cash Flow Assistant - Business Document

## 1. Overview

The Cash Flow Assistant is an intelligent agent designed to help Fund Managers (FMs) get a clear picture of cash availability across their funds and make informed decisions about capital calls.

### Purpose

> Help the Fund Manager answer: **"Do I have enough cash across my funds, and if not, what should I do about it?"**

### Key Capabilities

| Capability | Description |
|------------|-------------|
| Data Freshness Monitoring | Ensures reports are generated only on current, reliable data |
| Proactive Reminders | Notifies operations team to update data before report generation |
| Multi-Fund Analysis | Consolidates cash position across multiple funds and their SPVs |
| Actionable Recommendations | Provides clear capital call recommendations when shortfall is detected |

---

## 2. Who Uses This?

| Role | How They Use It |
|------|-----------------|
| **Fund Manager (FM)** | Receives monthly summary email, views detailed reports, makes capital call decisions |
| **CFO** | Receives monthly summary email, monitors portfolio cash health |
| **Operations / Preparer** | Receives reminder notifications, updates cash and investment data |

---

## 3. How It Works

### The Monthly Cycle

```
Week 1-3           Week 4 (T-7 to T-1)        Month End
    │                      │                      │
    ▼                      ▼                      ▼
Normal                 Reminder              Report
Operations             Window                Generated
                           │                      │
                           ▼                      ▼
                    Daily checks            Email to FM
                    Notify preparer         In-app reports
```

### Phase-by-Phase Breakdown

#### Phase A: Normal Operations (Week 1-3)

Business as usual. Preparers update account entries and proforma investments as part of regular work.

#### Phase B: Reminder Window (T-7 days before report)

The system starts checking data freshness daily and sends notifications to the operations team.

| Day | Data Status | Notification Sent |
|-----|-------------|-------------------|
| T-7 | Fund I: Fresh, Fund II: Stale | "Fund II needs update - 7 days to report" |
| T-5 | Fund I: Fresh, Fund II: Stale | "Fund II still needs update - 5 days left" |
| T-3 | Fund I: Fresh, Fund II: Fresh | "All data current - report ready" |
| T-1 | Fund I: Fresh, Fund II: Fresh | "Report generates tomorrow" |

#### Phase C: Report Generation Day

The agent runs and performs the following:

1. **Final Data Check**: Verifies all fund data is fresh
2. **Calculation**: Computes cash position, upcoming outflows, expenses
3. **Status Assignment**: Determines Surplus / Watch / Shortfall status
4. **Output Generation**: Creates email summary and in-app reports

---

## 4. Data Freshness Rules

The system will **not generate a report** for a fund if its data is stale. This ensures the FM never sees misleading information.

### What is "Stale Data"?

| Data Type | Stale If Older Than | Example |
|-----------|---------------------|---------|
| Cash Account Entries | Configurable (e.g., 30 days) | Bank balance not updated in 35 days |
| Proforma Investments | Configurable (e.g., 90 days) | Expected investment created 95 days ago |

### Why Block Stale Reports?

A report based on 45-day-old bank balances could lead to wrong capital call decisions. **No report is better than a misleading report.**

---

## 5. The Calculation

For each fund (including its SPVs), the system calculates:

| Component | Description |
|-----------|-------------|
| **Cash Available** | Sum of all cash accounts (bank, FD, liquid funds) |
| **Upcoming Investments** | Proforma investments with positive expected amount |
| **Estimated Expenses** | Based on tagged expense accounts |
| **Buffer Required** | Minimum cash reserve to maintain |
| **Net Position** | Cash - Investments - Expenses - Buffer |
| **Runway** | Days until cash runs out at current rate |

### Status Assignment

| Status | Condition | Meaning |
|--------|-----------|---------|
| Surplus | Net Position > 0, Runway > 90 days | Healthy cash position |
| Watch | Net Position > 0, Runway 30-90 days | Monitor closely |
| Shortfall | Net Position < 0 | Capital call needed |
| Blocked | Data is stale | Report cannot be generated |

---

## 6. Output: What the FM Receives

### Email Summary (Portfolio Level)

The FM receives a single email covering all configured funds:

**Subject**: Cash Flow Update - March 2026 - Action Required

| Fund | Status | Net Position | Runway | Recommended Action |
|------|--------|--------------|--------|-------------------|
| Apex Growth Fund I | Surplus | +3.20 Cr | 120 days | None |
| Apex Growth Fund II | Shortfall | -7.00 Cr | 18 days | Capital Call 8.00 Cr |
| Apex Opportunities III | Watch | +0.50 Cr | 45 days | Monitor |
| Apex Early Stage IV | Blocked | -- | -- | Update stale data |

**Action Items highlighted at top:**
- Fund II: Capital call of 8.00 Cr recommended by 15-Mar

### In-App Detailed Report (Per Fund)

Each fund has a "Cash Flow Analysis" page showing:

1. **Executive Summary**: Cash available, net position, runway, status
2. **Cash by Entity**: Breakdown by fund and each SPV
3. **Upcoming Investments**: List of proforma investments with expected dates
4. **Estimated Expenses**: Category-wise expense projection
5. **Undrawn Capital**: Available capacity for capital call
6. **Data Quality**: Freshness status of all data sources

---

## 7. Configuration Options

The agent is configured once and runs automatically on schedule.

### Fund Selection

| Option | Description |
|--------|-------------|
| All Funds | Include all funds managed by the FM |
| Selected Funds | Choose specific funds to include |

### Per-Fund Settings

| Setting | Description | Example |
|---------|-------------|---------|
| Cash Staleness Threshold | Maximum age of cash account data | 30 days |
| Proforma Staleness Threshold | Maximum age of proforma data | 90 days |

### Reminder Settings

| Setting | Description | Example |
|---------|-------------|---------|
| Reminder Window | Days before report to start reminders | 7 days |
| Reminder Recipients | Who receives the reminders | ops@company.com |

### Report Settings

| Setting | Description | Example |
|---------|-------------|---------|
| Report Recipients | Who receives the final report | fm@company.com, cfo@company.com |

### Account Tags

| Tag Type | Description | Example Tags |
|----------|-------------|--------------|
| Cash Accounts | Accounts to sum for cash position | Cash, Bank, Fixed Deposit, Liquid MF |
| Expense Accounts | Accounts for expense estimation | Mgmt Fees, Legal, Audit, Admin |
| Buffer Account | Account for buffer/reserve | Buffer Cash |

---

## 8. Scenarios

### Scenario 1: All Data Fresh - Report Generated

**Situation**: All funds have current data on report day.

**Result**:
- Full report generated for all funds
- Email sent to FM with portfolio summary
- Each fund's Cash Flow Analysis page updated

### Scenario 2: One Fund Has Stale Data

**Situation**: Fund I and Fund III have fresh data, Fund II has stale data.

**Result**:
- Report generated for Fund I and Fund III
- Fund II marked as "Blocked" in the summary
- Separate alert sent to preparer for Fund II
- FM sees: "Fund II report blocked - please contact operations"

### Scenario 3: All Funds Have Stale Data

**Situation**: No fund has current data on report day.

**Result**:
- No report generated
- FM notified: "Report could not be generated - all funds have stale data"
- Operations team notified with specific details per fund

---

## 9. Benefits

| Benefit | Description |
|---------|-------------|
| **Data Quality Assurance** | Reports only generated on fresh, reliable data |
| **Proactive Notifications** | Operations team reminded before deadlines |
| **Consolidated View** | All funds visible in one summary |
| **Clear Recommendations** | Specific capital call amounts recommended |
| **Time Savings** | No manual consolidation of Excel sheets |
| **Audit Trail** | Reports saved in-app for reference |

---

## 10. Phase 2 (Future Enhancements)

The following features are planned for future phases:

| Feature | Description |
|---------|-------------|
| Detailed Suggestions for "Watch" Status | Specific recommendations when runway is thin |
| Distribution Recommendations | Suggest distributions when excess cash exists |
| Stress Testing | "What if" scenarios for expense surge or realization delays |
| Trend Analysis | Historical comparison of forecasts vs actuals |
