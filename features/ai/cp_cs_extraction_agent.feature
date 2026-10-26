Feature: CP/CS Extraction Agent
  As a fund manager and counsel
  I want the CP/CS agent to extract obligations from portfolio investment documents
  So that conditions precedent and subsequent are tracked with tasks and alerts

  # The CP/CS Extraction Agent extends SideLetterObligationAgent for portfolio
  # investment agreements (SHA, SSA, SPA). It extracts obligations, deduplicates
  # them by source clause, and queues them for counsel review — same lifecycle as
  # SLO, but linked to portfolio investments via the sourceable polymorphic.
  #
  # ```mermaid
  # sequenceDiagram
  #   participant GP as GP Ops
  #   participant A as CpCsExtractionAgent
  #   participant UI as Obligation Matrix
  #   participant T as Task system
  #   GP->>A: Run agent on PortfolioInvestment (or Investor)
  #   A->>A: Locate tagged document (e.g. SHA)
  #   A->>A: LLM extracts obligations with source citations
  #   A->>UI: Obligations pending review
  #   GP->>UI: Approve → tasks projected
  #   GP->>UI: Fire armed obligation → dated task
  # ```

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a portfolio company "Acme Corp" with a fund and investment
    And there is a CP/CS extraction agent configured with tag "SHA"
    And the LLM extracts standard CP/CS obligations

  # ── 1. Single portfolio investment extraction ─────────────────────────────

  @cp_cs @extraction
  Scenario: Extract obligations from a single portfolio investment
    Given the portfolio investment has a document tagged "SHA"
    When the CP/CS agent runs for the portfolio investment
    Then 3 obligations should be pending review for the portfolio investment
    And no tasks should exist for any obligation
    And each obligation should be linked to the portfolio investment via sourceable

  # ── 2. Citation guard — uncited obligations discarded ─────────────────────

  @cp_cs @extraction @citation_guard
  Scenario: Obligations without source clause citations are discarded
    Given the portfolio investment has a document tagged "SHA"
    When the CP/CS agent runs for the portfolio investment
    Then 3 obligations should be pending review for the portfolio investment
    And the agent report should note discarded items for missing citation

  # ── 3. No document found — graceful skip ──────────────────────────────────

  @cp_cs @extraction @no_document
  Scenario: No tagged document produces no obligations
    When the CP/CS agent runs for the portfolio investment
    Then 0 obligations should be pending review for the portfolio investment

  # ── 4. Company-level extraction (Investor target) ─────────────────────────

  @cp_cs @extraction @company_level
  Scenario: Running against a portfolio company extracts from all its investments
    Given the portfolio company has 3 investments with documents tagged "SHA"
    When the CP/CS agent runs for the portfolio company
    Then 9 obligations should be pending review across all investments
    And each investment should have 3 obligations linked via sourceable

  # ── 5. Company-level with mixed documents ─────────────────────────────────

  @cp_cs @extraction @company_level @mixed
  Scenario: Investments without tagged documents are skipped gracefully
    Given the portfolio company has 3 investments with documents tagged "SHA"
    And the portfolio company has 1 investment without a tagged document
    When the CP/CS agent runs for the portfolio company
    Then 9 obligations should be pending review across all investments

  # ── 6. Idempotent re-extraction ───────────────────────────────────────────

  @cp_cs @extraction @idempotent
  Scenario: Re-extraction updates pending obligations without duplicating
    Given the portfolio investment has a document tagged "SHA"
    And the CP/CS agent has already run for the portfolio investment
    When the CP/CS agent runs for the portfolio investment again
    Then 3 obligations should be pending review for the portfolio investment

  # ── 7. Re-extraction creates delta for approved obligations ───────────────

  @cp_cs @extraction @delta
  Scenario: Changed content on an approved obligation creates a delta
    Given the portfolio investment has a document tagged "SHA"
    And the CP/CS agent has already run for the portfolio investment
    And the "Board approval before closing" CP/CS obligation is approved
    When the LLM extracts a changed CP obligation
    And the CP/CS agent runs for the portfolio investment again
    Then a pending delta obligation should exist for the changed clause

  # ── 8. Obligation lifecycle — approve and project tasks ───────────────────

  @cp_cs @lifecycle
  Scenario: Approving a one-time CP obligation creates a task
    Given the portfolio investment has a document tagged "SHA"
    And the CP/CS agent has already run for the portfolio investment
    When the CP/CS obligation "Board approval before closing" is approved
    Then exactly 1 task should exist for the CP/CS obligation
    And the task category should be "Condition Precedent"

  # ── 9. Armed CP obligation — fire with deadline ──────────────────────────

  @cp_cs @lifecycle @fire
  Scenario: Firing an armed CP obligation creates a dated task
    Given the portfolio investment has a document tagged "SHA"
    And the CP/CS agent has already run for the portfolio investment
    When the CP/CS obligation "Regulatory clearance notice" is approved
    Then the CP/CS obligation should be armed
    When the CP/CS obligation is fired with a due date 10 days out
    Then exactly 1 task should exist for the CP/CS obligation

  # ── 10. Obligation show page — no nil crashes for portfolio obligations ───

  @cp_cs @ui
  Scenario: Portfolio obligation show page renders without errors
    Given the portfolio investment has a document tagged "SHA"
    And the CP/CS agent has already run for the portfolio investment
    When I visit the CP/CS obligation page for "Board approval before closing"
    Then I should see "Acme Corp" on the obligation page
    And I should see the fund name on the obligation page
