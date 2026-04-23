Feature: LP Assistant Tools
  As a Limited Partner (investor)
  I want the LP Assistant tools to enforce my access scope
  So that I only see data for funds I am authorised to view

  Background:
    Given there is a user "first_name=LP-Analyst" for an entity "entity_type=Investment Fund;name=Angelia FM"
    And there is a fund "name=Angelia Growth Fund" for the entity
    And an LP scope is set up with entity "Angelia FM" and fund "Angelia Growth Fund"

  # ─── RunQueryTool: placeholder enforcement ─────────────────────────────────

  Scenario: Query missing {ENTITY_ID} placeholder is rejected
    When the LP runs the query "SELECT id FROM funds WHERE id IN ({FUND_IDS})"
    Then the query response should include "missing {ENTITY_ID}"

  Scenario: Query missing {FUND_IDS} placeholder is rejected
    When the LP runs the query "SELECT id FROM funds WHERE entity_id IN ({ENTITY_ID})"
    Then the query response should include "missing {FUND_IDS}"

  # ─── RunQueryTool: SQL guards ──────────────────────────────────────────────

  Scenario: Non-SELECT query is rejected
    When the LP runs the query "UPDATE funds SET name='x' WHERE entity_id IN ({ENTITY_ID}) AND id IN ({FUND_IDS})"
    Then the query response should include "only SELECT queries are allowed"

  Scenario: Forbidden keyword query is rejected
    When the LP runs the query "SELECT id FROM funds WHERE entity_id IN ({ENTITY_ID}) AND id IN ({FUND_IDS}); DROP TABLE funds"
    Then the query response should include "forbidden keyword"

  Scenario: Query against a non-whitelisted table is rejected
    When the LP runs the query "SELECT id FROM users WHERE entity_id IN ({ENTITY_ID}) AND id IN ({FUND_IDS})"
    Then the query response should include "tables not allowed"

  # ─── RunQueryTool: scope substitution ──────────────────────────────────────

  Scenario: Valid query is executed with LP scope substituted
    When the LP runs the query "SELECT id FROM funds WHERE entity_id IN ({ENTITY_ID}) AND id IN ({FUND_IDS})"
    Then the query response should list the LP's fund id

  Scenario: LP with no accessible funds gets a short-circuit message
    Given the LP scope is cleared of all accessible funds
    When the LP runs the query "SELECT id FROM funds WHERE entity_id IN ({ENTITY_ID}) AND id IN ({FUND_IDS})"
    Then the query response should include "No accessible funds"

  # ─── ListSkillsTool / LoadSkillTool ────────────────────────────────────────

  Scenario: list_skills exposes the LP Assistant data domains
    When the LP calls list_skills
    Then the skills response should list "fund_ratios"
    And the skills response should list "commitments"
    And the skills response should list "documents"

  Scenario: load_skill returns the markdown body for a known skill
    When the LP loads the skill "fund_ratios"
    Then the skill response should include "fund_ratios"

  Scenario: load_skill rejects an unknown skill
    When the LP loads the skill "does_not_exist"
    Then the skill response should include "not found"

  Scenario: load_skill sanitizes path traversal attempts
    When the LP loads the skill "../../etc/passwd"
    Then the skill response should include "not found"

  # ─── DocumentUrlTool ───────────────────────────────────────────────────────

  Scenario: LP can resolve a URL for a fund document within scope
    Given a fund document "Fund Report Q1" is attached to the LP's fund
    When the LP requests the URL for that document
    Then the document response should not include "not found"
    And the document response should not include "not accessible"

  Scenario: LP cannot resolve a URL for a document owned by another fund
    Given a fund document "Other Fund Report" is attached to a fund outside the LP's scope
    When the LP requests the URL for that document
    Then the document response should include "not found or not accessible"

  Scenario: LP cannot resolve a URL for a document with an unsupported owner_type
    Given a document with unsupported owner_type is created under the LP's entity
    When the LP requests the URL for that document
    Then the document response should include "not found or not accessible"
