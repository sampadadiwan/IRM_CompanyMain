Feature: FundRatioRun#resolved_portfolio_companies

  Returns the exact set of portfolio companies a run will process, based on the stored
  filters. Resolution rules:
    - No filters at all          → nil  (caller treats nil as "all companies, no scoping")
    - Explicit IDs only          → those companies
    - Tags only                  → OR within tags: any company matching any tag
    - Sectors only               → OR within sectors: any company in any sector
    - Tags + sectors together    → AND: company must match at least one tag AND be in at least one sector
    - Explicit IDs               → always included, bypassing the tags+sectors AND rule
    - Filters set, nothing found → entity.investors.none (not nil), so callers get zero results

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    And the entity has portfolio companies for resolved_portfolio_companies testing:
      | name     | sector      | tag_list |
      | Alpha Co | Fintech     | growth   |
      | Beta Co  | Healthcare  | stable   |
      | Gamma Co | Fintech     | stable   |
      | Delta Co | Healthcare  | growth   |

  # Alpha Co: Fintech / growth
  # Beta Co:  Healthcare / stable
  # Gamma Co: Fintech / stable   ← only company in both Fintech sector AND stable tag
  # Delta Co: Healthcare / growth

  # ─── No filters ─────────────────────────────────────────────────────────────

  Scenario: No filters returns nil
    Given a FundRatioRun exists with no portfolio company filters
    Then resolved_portfolio_companies should be nil

  # ─── Explicit IDs only ───────────────────────────────────────────────────────

  Scenario: Explicit IDs only returns exactly those companies
    Given a FundRatioRun exists with explicit companies "Alpha Co, Beta Co"
    Then resolved_portfolio_companies should return exactly "Alpha Co, Beta Co"

  # ─── Tags only ───────────────────────────────────────────────────────────────

  Scenario: Single tag returns all companies with that tag
    Given a FundRatioRun exists with tags "growth"
    Then resolved_portfolio_companies should return exactly "Alpha Co, Delta Co"

  Scenario: Multiple tags are OR'd — any matching tag is sufficient
    Given a FundRatioRun exists with tags "growth, stable"
    Then resolved_portfolio_companies should return exactly "Alpha Co, Beta Co, Gamma Co, Delta Co"

  # ─── Sectors only ────────────────────────────────────────────────────────────

  Scenario: Single sector returns all companies in that sector
    Given a FundRatioRun exists with sectors "Fintech"
    Then resolved_portfolio_companies should return exactly "Alpha Co, Gamma Co"

  Scenario: Multiple sectors are OR'd — any matching sector is sufficient
    Given a FundRatioRun exists with sectors "Fintech, Healthcare"
    Then resolved_portfolio_companies should return exactly "Alpha Co, Beta Co, Gamma Co, Delta Co"

  # ─── Tags + sectors (AND) ────────────────────────────────────────────────────

  Scenario: Tags and sectors together require a company to match both
    Given a FundRatioRun exists with tags "stable" and sectors "Fintech"
    Then resolved_portfolio_companies should return exactly "Gamma Co"

  Scenario: Multiple tags and a sector — OR within tags then AND with sector
    Given a FundRatioRun exists with tags "growth, stable" and sectors "Fintech"
    Then resolved_portfolio_companies should return exactly "Alpha Co, Gamma Co"

  Scenario: A tag and multiple sectors — OR within sectors then AND with tag
    Given a FundRatioRun exists with tags "growth" and sectors "Fintech, Healthcare"
    Then resolved_portfolio_companies should return exactly "Alpha Co, Delta Co"

  # ─── Empty intersection ───────────────────────────────────────────────────────

  Scenario: Tags and sectors with no common company returns empty (not nil)
    Given a FundRatioRun exists with tags "growth" and sectors "SaaS"
    Then resolved_portfolio_companies should return no companies

  # ─── Explicit IDs bypass the AND rule ────────────────────────────────────────

  Scenario: Explicit IDs are always included even when they do not match the tag+sector AND
    Given a FundRatioRun exists with explicit companies "Beta Co", tags "growth", and sectors "Fintech"
    Then resolved_portfolio_companies should return exactly "Alpha Co, Beta Co"

  Scenario: Explicit IDs are included even when tags-and-sectors intersection is empty
    Given a FundRatioRun exists with explicit companies "Beta Co", tags "growth", and sectors "SaaS"
    Then resolved_portfolio_companies should return exactly "Beta Co"
