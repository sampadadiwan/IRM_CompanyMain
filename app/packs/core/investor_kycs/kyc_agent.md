
# Onboarding Agent (Investor KYC) — Requirements

## 1. Purpose

The Onboarding Agent ensures that investor KYC records are complete, consistent, and compliant. It gives funds clear visibility into onboarding progress, sends reminders when needed, and triggers AML checks once verification is done. The focus is on **predictability** and **simplicity**: a static plan of checks that runs daily and/or when new KYC data arrives.

---

## 2. Triggers

* **Scheduled runs**: Executes at regular intervals (e.g., daily).
* **Event runs**: Executes immediately on events such as:

  * New `InvestorKyc` created.
  * A document uploaded.
  * A KYC field updated.

---

## 3. Inputs

* **InvestorKyc record**: contains declared fields.
* **FormCustomField**: defines which fields are mandatory or optional, and format/validation rules.
* **Uploaded documents**: passport, ID, proof of address, tax certificate, etc.
* **Document-to-field mapping**: defines which fields must be extracted and checked from each document.
* **Prompts for ad-hoc checks**: optional prompts that can query either fields or documents for additional validations.
* **Reminder configuration**: date or conditions under which reminder emails should be sent (existing reminder API is used).

---

## 4. Core Functions

### 4.1 Field Completeness

* Verify all mandatory fields are filled in.
* Flag missing or invalid values (e.g., wrong format, placeholder text).

### 4.2 Document Presence

* Verify all required documents are uploaded.
* Check for expirations (e.g., passport validity).
* Flag missing or expired documents.

### 4.3 Field-to-Document Consistency

* Extract data from uploaded documents using LLM prompts.
* Match extracted data to KYC fields:

  * **Exact match** for sensitive fields (DOB, tax ID, passport number).
  * **Fuzzy match** for fields like name or address.
* Flag mismatches for review.

### 4.4 Ad-hoc Checks

* Run additional prompt-based checks (e.g., source of funds red flags, jurisdiction-specific eligibility).
* Record results as informational, warning, or blocking issues.

### 4.5 Progress Reporting

* **Per-investor report** (`InvestorKycCompletionReport`):

  * Mandatory fields status.
  * Required documents status.
  * Consistency checks.
  * Ad-hoc checks.
  * Overall status (*Incomplete | Pending Review | Complete*).
* **Per-fund report** (`FundCompletionReport`):

  * Daily, weekly, and overall summaries.
  * % investors completed vs pending.
  * Common bottlenecks (e.g., missing proof of address).
  * Trend in onboarding completion.

### 4.6 Reminders

* Use existing Reminder API.
* Triggered either:

  * On a date specified in the agent prompt.
  * Or when blocking items remain unresolved for too long.
* Content is tailored to what’s missing (e.g., “Please upload proof of address”).

### 4.7 AML Auto-Trigger

* Once an investor’s KYC is marked **verification complete**:

  * Automatically trigger the existing AML function.
  * Record AML status in the investor’s report.

---

## 5. Execution & State

* The agent always runs the same **static sequence of checks**:

  1. Field completeness.
  2. Document presence.
  3. Field-to-document consistency.
  4. Ad-hoc checks.
  5. Reminder scheduling/firing.
  6. AML trigger.
* Each run maintains state:

  * Tasks can be `completed`, `skipped`, `failed`, or `pending review`.
* History is preserved so progress over time is visible.

---

## 6. Success Criteria

* No investor marked complete with missing mandatory fields or documents.
* Mismatches between fields and documents are consistently detected.
* Progress reports reflect daily/weekly trends without manual effort.
* Reminders go out on the right date and contextually reference missing items.
* AML checks are triggered automatically and logged.

