Feature: Support agent configuration health checks (all agents)
  As a fund manager
  I want every support agent to surface broken or missing configuration
  So that silent no-op runs are visible before they happen

  # Each agent overrides SupportAgentService.config_issues with checks for the
  # configuration it depends on at runtime. The shared banner on the agent show
  # page renders whatever the agent's service class reports.
  #
  # ```mermaid
  # sequenceDiagram
  #   participant U as Fund Manager
  #   participant SP as Agent Show Page
  #   participant SC as Agent Service Class
  #   U->>SP: open agent page
  #   SP->>SC: config_issues(support_agent)
  #   SC-->>SP: issues (unset toggles, blank recipients, missing templates)
  #   SP-->>U: warning banner before any run
  # ```

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"

  # ── Shared banner works for any agent type ───────────────────────────────

  Scenario: Misconfigured non-scoring agent shows the warning banner on its page
    Given there is a support agent "agent_type=DistributionReadinessAgent;name=Dist Readiness;enabled=true"
    When I visit the support agent page
    Then I should see the configuration warning banner

  # ── DistributionReadinessAgent ───────────────────────────────────────────

  Scenario: Distribution readiness warns when verification toggles are unset
    Given there is a support agent "agent_type=DistributionReadinessAgent;name=Dist Readiness;enabled=true"
    Then the agent config issues should include "'check_kyc' is not set"
    And the agent config issues should include "All verification checks are disabled"

  Scenario: Distribution readiness is healthy when all checks are configured
    Given there is a support agent "agent_type=DistributionReadinessAgent;name=Dist Readiness;enabled=true"
    And the agent json fields are:
      """
      {"check_kyc":"Yes","check_net_payable":"Yes","check_docs_generated":"Yes","check_docs_approved":"Yes","check_bank_details":"Yes"}
      """
    Then the agent config issues should be empty

  Scenario: Distribution readiness flags funds without a Distribution Template
    Given there is a support agent "agent_type=DistributionReadinessAgent;name=Dist Readiness;enabled=true"
    And the agent json fields are:
      """
      {"check_kyc":"Yes","check_net_payable":"Yes","check_docs_generated":"Yes","check_docs_approved":"Yes","check_bank_details":"Yes"}
      """
    And there is an existing fund "name=Growth Fund"
    Then the agent config issues should include "Fund 'Growth Fund' has no Distribution Template"

  # ── CashFlowAssistantAgent ───────────────────────────────────────────────

  Scenario: Cash flow assistant warns on empty configuration
    Given there is a support agent "agent_type=CashFlowAssistantAgent;name=Cash Flow;enabled=true"
    Then the agent config issues should include "No funds configured"
    And the agent config issues should include "'cash_tags' is blank"
    And the agent config issues should include "'report_recipients' is blank"

  Scenario: Cash flow assistant is healthy when configured for a real fund
    Given there is a support agent "agent_type=CashFlowAssistantAgent;name=Cash Flow;enabled=true"
    And there is an existing fund "name=Growth Fund"
    And the cash flow agent is configured for the existing fund
    Then the agent config issues should be empty

  Scenario: Cash flow assistant flags fund ids that no longer exist
    Given there is a support agent "agent_type=CashFlowAssistantAgent;name=Cash Flow;enabled=true"
    And the agent json fields are:
      """
      {"funds":[{"fund_id":999999,"name":"Ghost Fund"}],"cash_tags":"Cash","report_recipients":"ops@example.com"}
      """
    Then the agent config issues should include "999999 no longer exist"

  # ── DealManagementAgent ──────────────────────────────────────────────────

  Scenario: Deal management warns on unset toggles and missing digest email
    Given there is a support agent "agent_type=DealManagementAgent;name=Deal Mgmt;enabled=true"
    Then the agent config issues should include "'weekly_summary' is not set"
    And the agent config issues should include "'notify_email' is blank"

  # ── KycDocExtractorAgent ─────────────────────────────────────────────────

  Scenario: KYC doc extractor warns when no extraction rules exist
    Given there is a support agent "agent_type=KycDocExtractorAgent;name=KYC Extractor;enabled=true"
    Then the agent config issues should include "No extraction rules configured"

  Scenario: KYC doc extractor flags rules keyed to deleted form types
    Given there is a support agent "agent_type=KycDocExtractorAgent;name=KYC Extractor;enabled=true"
    And the agent json fields are:
      """
      {"extraction_rules":{"999999":[{"doc_label":"Upload Tax ID","prompt":"x","target_field":"PAN"}]}}
      """
    Then the agent config issues should include "999999"

  # ── DataQualityAgent ─────────────────────────────────────────────────────

  Scenario: Data quality warns when every check is disabled
    Given there is a support agent "agent_type=DataQualityAgent;name=Data Quality;enabled=true"
    Then the agent config issues should include "All data checks are disabled"

  Scenario: Data quality flags blank staleness thresholds
    Given there is a support agent "agent_type=DataQualityAgent;name=Data Quality;enabled=true"
    And the agent json fields are:
      """
      {"check_missing_valuations":"Yes","check_commitment_overflows":"Yes","check_stale_fx_rates":"Yes","send_report":"No","stale_valuation_days":""}
      """
    Then the agent config issues should include "'stale_valuation_days' is blank"

  # ── RtaReconciliationAgent ───────────────────────────────────────────────

  Scenario: RTA reconciliation warns on missing tolerances and unit settings without ISIN
    Given there is a support agent "agent_type=RtaReconciliationAgent;name=RTA Recon;enabled=true"
    And there is an existing fund "name=Growth Fund"
    And the fund has a unit setting "Series A" without ISIN
    Then the agent config issues should include "No reconciliation tolerance configured"
    And the agent config issues should include "Unit type 'Series A' of fund 'Growth Fund' has no ISIN"

  Scenario: RTA reconciliation flags send_report without a notify email
    Given there is a support agent "agent_type=RtaReconciliationAgent;name=RTA Recon;enabled=true"
    And the agent json fields are:
      """
      {"send_report":"Yes","check_pending_requests":"No","tolerance_units":"0.01","tolerance_pct":"0.1"}
      """
    Then the agent config issues should include "'send_report' is enabled but 'notify_email' is blank"

  # ── EsignMonitorAgent ────────────────────────────────────────────────────

  Scenario: Esign monitor flags a notify tag that matches no employees
    Given there is a support agent "agent_type=EsignMonitorAgent;name=Esign Monitor;enabled=true"
    And the agent json fields are:
      """
      {"flag_expired":"Yes","notify_tag":"ops-team"}
      """
    Then the agent config issues should include "no employee carries that tag"

  # ── DealsReportAgent ─────────────────────────────────────────────────────

  Scenario: Deals report warns on missing recipients and wrong flag literals
    Given there is a support agent "agent_type=DealsReportAgent;name=Deals Report;enabled=true"
    And the agent json fields are:
      """
      {"include_updates":"Yes"}
      """
    Then the agent config issues should include "'report_recipients' is blank"
    And the agent config issues should include "'include_updates' is 'Yes' but only the exact value 'true'"

  # ── CallNoticeAgent ──────────────────────────────────────────────────────

  Scenario: Call notice flags funds without a Call Template
    Given there is a support agent "agent_type=CallNoticeAgent;name=Call Notice;enabled=true"
    And there is an existing fund "name=Growth Fund"
    Then the agent config issues should include "Fund 'Growth Fund' has no Call Template"

  # ── KycOnboardingAgent ───────────────────────────────────────────────────

  Scenario: KYC onboarding warns on unset validations and blank expiry thresholds
    Given there is a support agent "agent_type=KycOnboardingAgent;name=KYC Onboarding;enabled=true"
    And the agent json fields are:
      """
      {"check_expiry":"Yes","expiry_warning_days":"","validate_documents":"Yes","send_reminder":"No","trigger_aml":"No"}
      """
    Then the agent config issues should include "'validate_fields' is not set"
    And the agent config issues should include "'expiry_warning_days' is blank"

  # ── PortfolioCompanyAgent ────────────────────────────────────────────────

  Scenario: Portfolio company agent warns when reminders can never fire
    Given there is a support agent "agent_type=PortfolioCompanyAgent;name=PortCo Agent;enabled=true"
    And the agent json fields are:
      """
      {"send_kpi_reminder":"Yes","reminder_days":""}
      """
    Then the agent config issues should include "no reminder will ever fire"

  # ── NoteSummarizerAgent ──────────────────────────────────────────────────

  Scenario: Note summarizer warns when a tag filter is set but tagging is off
    Given there is a support agent "agent_type=NoteSummarizerAgent;name=Note Summarizer;enabled=true"
    And the agent json fields are:
      """
      {"auto_tag_notes":"No","tag_filter":"Board Meeting"}
      """
    Then the agent config issues should include "'tag_filter' is set but 'auto_tag_notes' is off"
