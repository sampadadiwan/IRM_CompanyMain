Feature: Portfolio Scoring Agent configuration health check
  As a fund manager
  I want misconfigured skill files surfaced on the agent page
  So that I learn about broken setup before a run silently fails

  # The scoring agent needs File custom fields tagged "skill: true, sector: …"
  # plus an uploaded document named after each field's label. When either is
  # missing (e.g. meta_data drifted to blank on an old instance), runs fail
  # with only a log line — the banner and inline report error fix that.
  #
  # ```mermaid
  # sequenceDiagram
  #   participant U as Fund Manager
  #   participant SP as Agent Show Page
  #   participant PS as PortfolioScoringAgent
  #   participant ST as SupportAgentsSetupService
  #   U->>SP: open agent page
  #   SP->>PS: config_issues(support_agent)
  #   PS->>ST: skill_field_templates(agent_type)
  #   ST-->>PS: template skill fields
  #   PS-->>SP: issues (blank meta_data / missing upload)
  #   SP-->>U: warning banner before any run
  # ```

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"

  # ── Banner on the agent show page ────────────────────────────────────────

  Scenario: Warn when a skill field has blank meta data
    Given there is a portfolio scoring agent with skill fields having blank meta data
    When I visit the support agent page
    Then I should see the configuration warning banner
    And I should see a configuration issue "is not tagged as a skill"

  Scenario: Warn when a skill file has not been uploaded
    Given there is a portfolio scoring agent with tagged skill fields but no uploaded files
    When I visit the support agent page
    Then I should see the configuration warning banner
    And I should see a configuration issue "No skill file uploaded"

  Scenario: No warning when the agent is fully configured
    Given there is a fully configured portfolio scoring agent
    When I visit the support agent page
    Then I should not see the configuration warning banner

  # ── Isolation: skill-file checks never leak to other agent types ────────
  # (Other agents have their own config checks, so a healthy configuration is
  # set up here — the stray File field alone must not trigger a banner.)

  Scenario: Healthy other agents with File fields never show the banner
    Given there is a support agent "agent_type=PortfolioCompanyAgent;name=PortCo Analyst;enabled=true"
    And the agent json fields are:
      """
      {"send_kpi_reminder":"No"}
      """
    And the agent has a File custom field with blank meta data
    When I visit the support agent page
    Then I should not see the configuration warning banner

  # ── Failed runs show their reason inline in the reports tab ─────────────

  Scenario: Failed scoring report shows its error without expanding the row
    Given there is a portfolio scoring agent with skill fields having blank meta data
    And there is an existing portfolio company "name=GlowCo;category=Portfolio Company"
    And there is a failed scoring report with error "No skill file configured for sector: Beauty & Skincare"
    When I visit the support agent page scoring reports tab
    Then I should see "No skill file configured for sector: Beauty & Skincare" in the reports table

  # ── Setup service backfills drifted skill meta_data only ─────────────────

  Scenario: Setup service backfills blank meta data on skill fields only
    Given there is a portfolio scoring agent with skill fields having blank meta data
    And the agent has a File custom field with blank meta data
    When the support agent custom fields are re-synced from the template
    Then the skill fields should have their template meta data
    And the non-skill File field should still have blank meta data
