Feature: Capital Remittance Reconciliation Agent
  As a fund operations admin I want an agent that reads a bank statement workbook, parses
  every deposit narration through a bank-specific parser registry, and scores each deposit
  against one capital call's outstanding remittances — so I don't have to read raw RTGS/NEFT/
  IMPS narrations by hand or manually key a Folio No into a CSV importer. Covers ingestion,
  parsing, tiering, auto-applying Exact matches as payments (idempotently), the summary email,
  and the reviewer panel on the capital call page (Confirm / Reassign / Undo).

  Background:
    Given there is a user "first_name=RemitAdmin" for an entity "name=RemitTestEntity;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a RemittanceReconciliationAgent configured for the entity
    And there is a fund "name=Test Fund" for the entity
    And there is a capital call "{'First Close':'100'}" for the fund

  # ── 1. Agent registration ──────────────────────────────────────────────────

  @capital_remittance_reconciliation @registration
  Scenario: RemittanceReconciliationAgent is a recognised support agent type
    Then "RemittanceReconciliationAgent" is a recognised support agent type

  # ── 2. Missing statement ───────────────────────────────────────────────────

  @capital_remittance_reconciliation @validation
  Scenario: Running without an uploaded bank statement records a blocking issue
    When the RemittanceReconciliationAgent runs for the capital call without a bank statement
    Then a capital-call-level SupportAgentReport is saved
    And the reconciliation report has a blocking issue matching "No bank statement uploaded"

  # ── 3. ICICI narration parsing ─────────────────────────────────────────────

  @capital_remittance_reconciliation @parsing
  Scenario: An ICICI-style narration yields both name and account number at high confidence
    Given the bank statement has an ICICI sheet with deposit rows:
      | narration                                                              | amount    |
      | RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240 | 699842.06 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the report deposit_count is 1
    And the report lists a deposit with name "DEEPAKAGARWAL" and account "50100602457893" and confidence "high"

  # ── 4. Axis narration parsing ──────────────────────────────────────────────

  @capital_remittance_reconciliation @parsing
  Scenario: An Axis-style narration yields a name only, no account number
    Given the bank statement has an Axis sheet with deposit rows:
      | narration                | amount     |
      | TRF/SAMRATH BEDI/TRANSFER | 1049763.03 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the report lists a deposit with name "SAMRATH BEDI" and no account number

  # ── 5. Internal fund movements are kept, not dropped ───────────────────────

  @capital_remittance_reconciliation @internal
  Scenario: A fixed-deposit closure narration is marked internal, not silently dropped
    Given the bank statement has an Axis sheet with deposit rows:
      | narration                          | amount      |
      | 926040079793255 : Closure Proceeds | 30034521.00 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the report deposit_count is 1
    And the report internal_count is 1
    And the report lists an internal deposit with narration "926040079793255 : Closure Proceeds"

  # ── 6. Withdrawals are excluded entirely ───────────────────────────────────

  @capital_remittance_reconciliation @filtering
  Scenario: Withdrawal rows never appear in the report at all
    Given the bank statement has an ICICI sheet with a withdrawal row "SGB/3101499/PRAVEGA FUND II/Transfer" amount 19000000.0
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the report deposit_count is 0

  # ── 7. Multi-sheet, multi-bank workbook ─────────────────────────────────────

  @capital_remittance_reconciliation @multi_sheet
  Scenario: A workbook with one sheet per bank account parses every sheet
    Given the bank statement has an ICICI sheet with deposit rows:
      | narration                                                              | amount    |
      | RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240 | 699842.06 |
    And the bank statement also has an Axis sheet with deposit rows:
      | narration                | amount     |
      | TRF/SAMRATH BEDI/TRANSFER | 1049763.03 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the report deposit_count is 2

  # ── 8. Unrecognized bank falls back to the generic parser ─────────────────

  @capital_remittance_reconciliation @registry
  Scenario: A sheet with no recognised bank IFSC still parses via the generic fallback
    Given the bank statement has a sheet for an unrecognized bank with deposit rows:
      | narration                                                                     | amount    |
      | RTGS/HDFCR52026060566898048/MUKUL DHYANI/HDFC BANK//NRE/NRE///Pravega Fund II | 349920.97 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the report lists a deposit with name "MUKUL DHYANI" and no account number

  # ── 9. Unrecognized narration shape ────────────────────────────────────────

  @capital_remittance_reconciliation @validation
  Scenario: A narration matching no known pattern is flagged for manual review
    Given the bank statement has an ICICI sheet with deposit rows:
      | narration               | amount |
      | XYZQ123 SOMETHING WEIRD | 1000.0 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the reconciliation report has a warning issue matching "didn't match any known narration pattern"

  # ── 10. Re-running is safe ─────────────────────────────────────────────────

  @capital_remittance_reconciliation @idempotency
  Scenario: Running the agent again on the same statement creates a fresh report, not an error
    Given the bank statement has an ICICI sheet with deposit rows:
      | narration                                                              | amount    |
      | RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240 | 699842.06 |
    When the RemittanceReconciliationAgent runs for the capital call
    And the RemittanceReconciliationAgent runs again for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the report deposit_count is 1

  # ── 11. Exact match via KYC account ────────────────────────────────────────

  @capital_remittance_reconciliation @matching
  Scenario: Account number matching the investor's KYC record ties to Exact
    Given there is a remittance under the capital call for investor "Deepak Agarwal" with call amount 699842.06 and KYC bank account "50100602457893"
    And the bank statement has an ICICI sheet with deposit rows:
      | narration                                                              | amount    |
      | RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240 | 699842.06 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the deposit with narration "RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240" is tiered "exact"
    And the deposit with narration "RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240" has source_of_funds "confirmed"

  # ── 12. Exact match via virtual account, no KYC on file ─────────────────────

  @capital_remittance_reconciliation @matching
  Scenario: A virtual bank account match reaches Exact even with no KYC account on file
    Given there is a remittance under the capital call for investor "Kailash Sahebrao Katkar" with call amount 500000.0 and virtual bank account "921010040955101"
    And the bank statement has an Axis sheet with deposit rows:
      | narration                                        | amount   |
      | MOB/TPFT/KAILASH SAHEBRAO KATKAR/921010040955101 | 500000.0 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the deposit with narration "MOB/TPFT/KAILASH SAHEBRAO KATKAR/921010040955101" is tiered "exact"

  # ── 13. Probable match — name only, no account exposed ──────────────────────

  @capital_remittance_reconciliation @matching
  Scenario: A name-only match with amount within tolerance is Probable, not Exact
    Given there is a remittance under the capital call for investor "Samrath Bedi" with call amount 1049763.03
    And the bank statement has an Axis sheet with deposit rows:
      | narration                 | amount     |
      | TRF/SAMRATH BEDI/TRANSFER | 1049763.03 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the deposit with narration "TRF/SAMRATH BEDI/TRANSFER" is tiered "probable"

  # ── 14. Needs review — funding-source discrepancy ────────────────────────────

  @capital_remittance_reconciliation @matching
  Scenario: A narration account that contradicts the matched investor's KYC record is always flagged
    Given there is a remittance under the capital call for investor "Rahul Pradeep Rathi" with call amount 699842.06 and KYC bank account "50100999999999"
    And the bank statement has an ICICI sheet with deposit rows:
      | narration                                                                 | amount    |
      | RTGS-HDFCR5202606257 5228613-RAHULPRADEEPRATHI-50100000000001-HDFC0000240 | 699842.06 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the deposit with narration "RTGS-HDFCR5202606257 5228613-RAHULPRADEEPRATHI-50100000000001-HDFC0000240" is tiered "needs_review"
    And the deposit with narration "RTGS-HDFCR5202606257 5228613-RAHULPRADEEPRATHI-50100000000001-HDFC0000240" has source_of_funds "discrepancy"

  # ── 15. Needs review — overpayment beyond tolerance ─────────────────────────

  @capital_remittance_reconciliation @matching
  Scenario: An account match that overpays the due amount beyond tolerance is capped at Needs review and says why
    Given there is a remittance under the capital call for investor "Sandeep Kumar Singh" with call amount 349920.97 and KYC bank account "50100584951278"
    And the bank statement has an ICICI sheet with deposit rows:
      | narration                                                                  | amount    |
      | RTGS-HDFCR5202606237 4415905-SANDEEPKUMARSINGH-50100584951278-HDFC0000240 | 999999.99 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the deposit with narration "RTGS-HDFCR5202606237 4415905-SANDEEPKUMARSINGH-50100584951278-HDFC0000240" is tiered "needs_review"
    And the deposit with narration "RTGS-HDFCR5202606237 4415905-SANDEEPKUMARSINGH-50100584951278-HDFC0000240" has amount_status "overpaid"
    And the deposit with narration "RTGS-HDFCR5202606237 4415905-SANDEEPKUMARSINGH-50100584951278-HDFC0000240" has a reasoning line matching "overpayment"

  # ── 15b. Partial payment keeps its tier and records the amount received ─────

  @capital_remittance_reconciliation @matching @auto_apply
  Scenario: An account match that underpays the due amount is still Exact, flagged partial, and applies for the amount received
    Given there is a remittance under the capital call for investor "Sandeep Kumar Singh" with call amount 349920.97 and KYC bank account "50100584951278"
    And the agent's auto_apply_exact is "Yes"
    And the bank statement has an ICICI sheet with deposit rows:
      | narration                                                                  | amount    |
      | RTGS-HDFCR5202606237 4415905-SANDEEPKUMARSINGH-50100584951278-HDFC0000240 | 200000.00 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the deposit with narration "RTGS-HDFCR5202606237 4415905-SANDEEPKUMARSINGH-50100584951278-HDFC0000240" is tiered "exact"
    And the deposit with narration "RTGS-HDFCR5202606237 4415905-SANDEEPKUMARSINGH-50100584951278-HDFC0000240" has amount_status "partial"
    And the deposit with narration "RTGS-HDFCR5202606237 4415905-SANDEEPKUMARSINGH-50100584951278-HDFC0000240" has a reasoning line matching "partial payment"
    And the report payments_created is 1
    And the CapitalRemittancePayment for "Sandeep Kumar Singh" has amount 200000.0

  # ── 15c. A name-only partial payment stays Probable ──────────────────────────

  @capital_remittance_reconciliation @matching
  Scenario: A name-only match that underpays is Probable, not Needs review
    Given there is a remittance under the capital call for investor "Samrath Bedi" with call amount 1049763.03
    And the bank statement has an Axis sheet with deposit rows:
      | narration                 | amount    |
      | TRF/SAMRATH BEDI/TRANSFER | 500000.00 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the deposit with narration "TRF/SAMRATH BEDI/TRANSFER" is tiered "probable"
    And the deposit with narration "TRF/SAMRATH BEDI/TRANSFER" has amount_status "partial"

  # ── 15d. Same investor, two folios on the call, one KYC account ──────────────

  @capital_remittance_reconciliation @matching
  Scenario: A deposit from an investor holding two folios on the call is ambiguous and says which folios to pick from
    Given there is a remittance under the capital call for investor "Deepak Agarwal" with call amount 699842.06 and KYC bank account "50100602457893"
    And there is a second remittance under the capital call for the same investor "Deepak Agarwal" with call amount 300000.0
    And the bank statement has an ICICI sheet with deposit rows:
      | narration                                                              | amount    |
      | RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240 | 699842.06 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then the deposit with narration "RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240" is tiered "needs_review"
    And the deposit with narration "RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240" has a reasoning line matching "2 folios of the same investor"

  # ── 16. No match ─────────────────────────────────────────────────────────────

  @capital_remittance_reconciliation @matching
  Scenario: A depositor with no candidate remittance under this call is No match
    Given the bank statement has an ICICI sheet with deposit rows:
      | narration                                                                | amount   |
      | RTGS-HDFCR5202606257 9999999-NOBODYMATCHESME-99999999999999-HDFC0000240 | 100000.0 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the deposit with narration "RTGS-HDFCR5202606257 9999999-NOBODYMATCHESME-99999999999999-HDFC0000240" is tiered "no_match"

  # ── 17. Virtual account match contradicting the KYC account on file ─────────
  # The account number a narration exposes is the SENDER's account, virtual account included —
  # so when the investor also has a KYC-registered account and it differs, that is a
  # funding-source discrepancy exactly as it would be for a name match.

  @capital_remittance_reconciliation @matching
  Scenario: A virtual account match whose sender account contradicts the investor's KYC account is flagged
    Given there is a remittance under the capital call for investor "Priya Sharma" with call amount 250000.0 and KYC bank account "11112222333" and virtual bank account "444455556666"
    And the bank statement has an Axis sheet with deposit rows:
      | narration                          | amount   |
      | MOB/TPFT/PRIYA SHARMA/444455556666 | 250000.0 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the deposit with narration "MOB/TPFT/PRIYA SHARMA/444455556666" is tiered "needs_review"
    And the deposit with narration "MOB/TPFT/PRIYA SHARMA/444455556666" has source_of_funds "discrepancy"
    And the deposit with narration "MOB/TPFT/PRIYA SHARMA/444455556666" has a reasoning line matching "contradicts the investor's KYC-registered account 11112222333"

  # ── 18. auto_apply_exact defaults to No — zero payments despite an Exact match ──

  @capital_remittance_reconciliation @auto_apply
  Scenario: auto_apply_exact defaults to No, so an Exact match is tiered but never creates a payment
    Given there is a remittance under the capital call for investor "Deepak Agarwal" with call amount 699842.06 and KYC bank account "50100602457893"
    And the bank statement has an ICICI sheet with deposit rows:
      | narration                                                              | amount    |
      | RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240 | 699842.06 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the deposit with narration "RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240" is tiered "exact"
    And the report payments_created is 0

  # ── 19. auto_apply_exact = Yes creates a payment, and a re-run never duplicates it ─

  @capital_remittance_reconciliation @auto_apply
  Scenario: An Exact match auto-applies as a payment when enabled, and re-running is a safe no-op
    Given there is a remittance under the capital call for investor "Deepak Agarwal" with call amount 699842.06 and KYC bank account "50100602457893"
    And the agent's auto_apply_exact is "Yes"
    And the bank statement has an ICICI sheet with deposit rows:
      | narration                                                              | amount    |
      | RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240 | 699842.06 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the report payments_created is 1
    When the RemittanceReconciliationAgent runs again for the capital call
    Then the report payments_created is 0
    And the report payments_already_recorded is 1

  # ── 19b. Dedup is call-aware: a reference already applied to ANOTHER call is not claimed here ─

  @capital_remittance_reconciliation @auto_apply
  Scenario: A deposit already recorded against another capital call of the fund is reported as recorded elsewhere, never re-applied or offered for Undo here
    Given there is a remittance under the capital call for investor "Deepak Agarwal" with call amount 699842.06 and KYC bank account "50100602457893"
    And the agent's auto_apply_exact is "Yes"
    And the bank statement has an ICICI sheet with deposit rows:
      | narration                                                              | amount    |
      | RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240 | 699842.06 |
    And the deposit with tran id "TXN-1" was already recorded against another capital call of the fund for investor "Deepak Agarwal"
    When the RemittanceReconciliationAgent runs for the capital call
    Then a capital-call-level SupportAgentReport is saved
    And the report payments_created is 0
    And the report payments_recorded_elsewhere is 1
    And the deposit with narration "RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240" has payment_status "recorded_elsewhere"
    And the deposit with narration "RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240" has no payment_id
    And exactly 1 CapitalRemittancePayment exists on the fund with reference "TXN-1"

  # ── 19c. Foreign-currency folio: folio amount is derived through the fund's exchange rate ─

  @capital_remittance_reconciliation @auto_apply @multi_currency
  Scenario: A payment on a USD folio into an INR fund records the folio amount via the recorded exchange rate
    Given there is an exchange rate "from=INR;to=USD;as_of=2026-01-01;rate=0.012" for the entity
    And there is a remittance under the capital call for investor "Deepak Agarwal" with call amount 699842.06 and KYC bank account "50100602457893" in folio currency "USD"
    And the agent's auto_apply_exact is "Yes"
    And the bank statement has an ICICI sheet with deposit rows:
      | narration                                                              | amount    |
      | RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240 | 699842.06 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then the report payments_created is 1
    And the CapitalRemittancePayment for "Deepak Agarwal" has amount 699842.06
    And the CapitalRemittancePayment for "Deepak Agarwal" has folio amount 8398.1

  @capital_remittance_reconciliation @auto_apply @multi_currency
  Scenario: A payment on a USD folio with no exchange rate on file is refused rather than recorded with a zero folio amount
    Given there is no exchange rate from "INR" to "USD" for the entity
    And there is a remittance under the capital call for investor "Deepak Agarwal" with call amount 699842.06 and KYC bank account "50100602457893" in folio currency "USD"
    And the agent's auto_apply_exact is "Yes"
    And the bank statement has an ICICI sheet with deposit rows:
      | narration                                                              | amount    |
      | RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240 | 699842.06 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then the report payments_created is 0
    And the deposit with narration "RTGS-HDFCR5202606247 4674383-DEEPAKAGARWAL-50100602457893-HDFC0000240" has payment_status "error"
    And the reconciliation report has a warning issue matching "No exchange rate from INR to USD"

  # ── 19d. Summary email ───────────────────────────────────────────────────────

  @capital_remittance_reconciliation @email
  Scenario: The run summary is emailed to notify_email when send_report is Yes
    Given the agent's send_report is "Yes" and notify_email is "controller@example.com"
    And there is a remittance under the capital call for investor "Rahul Pradeep Rathi" with call amount 699842.06 and KYC bank account "50100999999999"
    And the bank statement has an ICICI sheet with deposit rows:
      | narration                                                                 | amount    |
      | RTGS-HDFCR5202606257 5228613-RAHULPRADEEPRATHI-50100000000001-HDFC0000240 | 699842.06 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then a reconciliation report email is sent to "controller@example.com" with subject matching "[RECON REVIEW]"
    And the reconciliation report email mentions "Rahul Pradeep Rathi"

  @capital_remittance_reconciliation @email
  Scenario: No email is sent when send_report is No
    Given the agent's send_report is "No" and notify_email is "controller@example.com"
    And the bank statement has an Axis sheet with deposit rows:
      | narration                 | amount     |
      | TRF/SAMRATH BEDI/TRANSFER | 1049763.03 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then no reconciliation report email is sent

  # ── 19e. Text amounts with Indian digit grouping ─────────────────────────────

  @capital_remittance_reconciliation @parsing
  Scenario: An amount cell exported as text with comma grouping is parsed as the full figure
    Given the bank statement has an Axis sheet with deposit rows:
      | narration                 | amount       |
      | TRF/SAMRATH BEDI/TRANSFER | 10,49,763.03 |
    When the RemittanceReconciliationAgent runs for the capital call
    Then the deposit with narration "TRF/SAMRATH BEDI/TRANSFER" has amount 1049763.03

  # ── 19f. Statement generator (rake remittance_reconciliation:statement) ──────

  @capital_remittance_reconciliation @generator
  Scenario: The statement generator writes the workbook into the feature's own sample_uploads subfolder and it parses back
    Given there is a remittance under the capital call for investor "Deepak Agarwal" with call amount 699842.06 and KYC bank account "50100602457893"
    And there is a remittance under the capital call for investor "Samrath Bedi" with call amount 1049763.03
    When the statement generator runs for the capital call with bank "icici"
    Then the generated workbook exists under "public/sample_uploads/remittance_reconciliation"
    And the generated workbook parses as an ICICI statement with 3 deposits

  # ── 20. Reconciliation panel visibility ─────────────────────────────────────

  @capital_remittance_reconciliation @ui
  Scenario: The reconciliation panel is visible on the Capital Call page when the entity flag is enabled
    Given there is a user "first_name=PanelAdmin" for an entity "name=PanelTestEntity;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has the capital_remittance_reconciliation_agent flag enabled
    And there is a RemittanceReconciliationAgent configured for the entity
    And there is a fund "name=Test Fund" for the entity
    And there is a capital call "{'First Close':'100'}" for the fund
    And there is an empty reconciliation report for the capital call
    When I visit the capital call page as the fund admin
    And I open the Reconciliation tab
    Then I should see the reconciliation panel
    When I open the capital call actions menu
    Then I should see the run reconciliation button

  @capital_remittance_reconciliation @ui
  Scenario: The Reconciliation tab is hidden and the menu item locked when the agent is provisioned but disabled
    Given there is a user "first_name=DisabledAdmin" for an entity "name=DisabledTestEntity;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has the capital_remittance_reconciliation_agent flag enabled
    And there is a RemittanceReconciliationAgent configured for the entity
    And the RemittanceReconciliationAgent is disabled
    And there is a fund "name=Test Fund" for the entity
    And there is a capital call "{'First Close':'100'}" for the fund
    When I visit the capital call page as the fund admin
    Then I should not see the Reconciliation tab
    When I open the capital call actions menu
    Then the run reconciliation menu item is locked

  @capital_remittance_reconciliation @ui
  Scenario: The reconciliation panel is hidden when the entity flag is not enabled
    Given there is a user "first_name=NoFlagAdmin" for an entity "name=NoFlagTestEntity;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a fund "name=Test Fund" for the entity
    And there is a capital call "{'First Close':'100'}" for the fund
    When I visit the capital call page as the fund admin
    Then I should not see the Reconciliation tab

  # ── 21. Confirm creates a payment ───────────────────────────────────────────

  @capital_remittance_reconciliation @ui
  Scenario: Confirming a Probable deposit creates a payment
    Given there is a user "first_name=ConfirmAdmin" for an entity "name=ConfirmTestEntity;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has the capital_remittance_reconciliation_agent flag enabled
    And there is a RemittanceReconciliationAgent configured for the entity
    And there is a fund "name=Test Fund" for the entity
    And there is a capital call "{'First Close':'100'}" for the fund
    And there is a remittance under the capital call for investor "Samrath Bedi" with call amount 1049763.03
    And there is a reconciliation report for the capital call with a probable deposit matched to "Samrath Bedi"
    When I visit the capital call page as the fund admin
    And I open the Reconciliation tab
    And I click "Confirm"
    And I proceed with the confirmation popup
    Then I should see the payment recorded confirmation
    And a CapitalRemittancePayment should exist for "Samrath Bedi"
    When I open the Reconciliation tab
    Then I should see "Payment recorded"
    And I should see "Undo"

  # ── 21b. Confirm all Exact ──────────────────────────────────────────────────

  @capital_remittance_reconciliation @ui
  Scenario: Confirm all Exact records every pending Exact row and leaves the Probable row alone
    Given there is a user "first_name=BulkAdmin" for an entity "name=BulkTestEntity;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has the capital_remittance_reconciliation_agent flag enabled
    And there is a RemittanceReconciliationAgent configured for the entity
    And there is a fund "name=Test Fund" for the entity
    And there is a capital call "{'First Close':'100'}" for the fund
    And there is a remittance under the capital call for investor "Deepak Agarwal" with call amount 699842.06 and KYC bank account "50100602457893"
    And there is a remittance under the capital call for investor "Sandeep Kumar Singh" with call amount 349920.97 and KYC bank account "50100584951278"
    And there is a remittance under the capital call for investor "Samrath Bedi" with call amount 1049763.03
    And there is a reconciliation report for the capital call with exact deposits for "Deepak Agarwal, Sandeep Kumar Singh" and a probable deposit for "Samrath Bedi"
    When I visit the capital call page as the fund admin
    And I open the Reconciliation tab
    And I click "Confirm all Matched (2)"
    And I confirm the bulk confirmation modal
    Then I should see "2 payments recorded"
    And a CapitalRemittancePayment should exist for "Deepak Agarwal"
    And a CapitalRemittancePayment should exist for "Sandeep Kumar Singh"
    And no CapitalRemittancePayment should exist for "Samrath Bedi"
    When I open the Reconciliation tab
    Then there is a Confirm button in the reconciliation table
    And there is no Confirm all Matched button

  # ── 22. Undo removes an auto-applied payment ────────────────────────────────

  @capital_remittance_reconciliation @ui
  Scenario: Undo removes an Exact auto-applied payment
    Given there is a user "first_name=RevertAdmin" for an entity "name=RevertTestEntity;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has the capital_remittance_reconciliation_agent flag enabled
    And there is a RemittanceReconciliationAgent configured for the entity
    And there is a fund "name=Test Fund" for the entity
    And there is a capital call "{'First Close':'100'}" for the fund
    And there is a remittance under the capital call for investor "Deepak Agarwal" with call amount 699842.06 and KYC bank account "50100602457893"
    And there is a reconciliation report for the capital call with an exact payment already recorded for "Deepak Agarwal"
    When I visit the capital call page as the fund admin
    And I open the Reconciliation tab
    And I click "Undo"
    And I proceed with the confirmation popup
    Then the CapitalRemittancePayment for "Deepak Agarwal" should be destroyed
    And I should see "Payment removed"
    When I open the Reconciliation tab
    Then there is a Confirm button in the reconciliation table
    And there is no Undo button in the reconciliation table
