Feature: Report owner cannot be re-assigned - 2026-10 security review (H17)
  The report form posted hidden entity_id and user_id fields and update applied them, so a report
  could be re-owned by another firm's user. AI insights run with the owner's visibility, so that
  user's rows went to the LLM and into this firm's insight email. The fields are gone, the owner must
  be in the report's firm whenever it is set or changed, and an insight whose owner is no longer in
  the report's firm is refused before any LLM call.
  Design and worked examples: docs/security/security_review_2026_10.md#h17--report-owner-mass-assignment

  Background:
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is another firm "Zeta Capital" with a user "Zoe"

  # H17-1 — Edge case: an update naming another firm's user (and firm) leaves the owner and firm as they were
  @security @rack_test
  Scenario: H17-1 Updating a report with another firm's user id keeps the owner
    Given I own a report "Artha Commitments"
    When I update the report sending "Zoe" of "Zeta Capital" as its owner and firm
    Then the report is still owned by "Gita" of "Artha"
    And the report is saved with name "Renamed by form"
    And re-owning the report to "Zoe" directly is refused

  # H17-2 — Edge case: the owner has left the firm (or a support owner is switched elsewhere): no insight runs
  @security @rack_test
  Scenario: H17-2 An insight for a report whose owner is in another firm is refused
    Given a user "Sam" of my firm owns a report "Support Commitments"
    And the report's owner has moved to "Zeta Capital"
    When the report's insight job runs
    Then the insight fails with "Report owner is no longer in this firm"
    And no LLM was asked and no insight email was sent

  # H17-H — Happy path: the company admin edits the recipients and the insight is generated
  @security @rack_test
  Scenario: H17-H Editing recipients and generating an insight still work
    Given I own a report "Artha Commitments"
    When I update the report's notification recipients to "ops@artha.example"
    Then the report is saved with notification recipients "ops@artha.example"
    When the report's insight job runs
    Then the insight is generated

  # H17-X — Edge case: a report created by a user switched into the firm stays editable after they leave
  @security @rack_test
  Scenario: H17-X A report whose owner left can still be renamed
    Given a user "Sam" of my firm owns a report "Support Commitments"
    And the report's owner has moved to "Zeta Capital"
    When I rename the report to "Renamed after leaving"
    Then the report is saved with name "Renamed after leaving"
    And the report is still owned by "Sam" of "Artha"
