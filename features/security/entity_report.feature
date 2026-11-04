Feature: Company report address removed - 2026-10 security review (H16)
  /entities/:id/report rendered any entities/ template named in its report parameter behind an
  always-true policy, so any signed-in user could render another company's edit form with its tax id
  and email. It had no caller left, so the action, its route and its policy rule are gone. The
  company page and the edit page keep their own rules.
  Design and worked examples: docs/security/security_review_2026_10.md#h16--entitiesreport

  Background:
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And batch 2 has another tenant "Zeta Capital" with PAN "ZETA12345P" and email "ir@zeta.example"

  # H16-1 — Edge case: a user of another company cannot render this company's edit form through the report address
  @security @rack_test
  Scenario: H16-1 Opening another company's report address with report=edit gets a 404
    When I open the report address of "Zeta Capital" with report "edit"
    Then the address is not found
    And neither "ZETA12345P" nor "ir@zeta.example" is in the response

  # H16-2 — Edge case: the address is gone for the company's own admin too
  @security @rack_test
  Scenario: H16-2 The company's own admin opening its report address gets a 404
    When I open the report address of "Artha" with report "edit"
    Then the address is not found

  # H16-H — Happy path: the company's admin still opens the edit page
  @security @rack_test
  Scenario: H16-H The company's admin opens its edit page
    When I open the edit page of my company
    Then I see my company's edit form

  # H16-H2 — Happy path: an unrelated user still opens another company's page and sees its public profile
  @security @rack_test
  Scenario: H16-H2 An unrelated user sees another company's public profile
    When I open the entity page of "Zeta Capital"
    Then I see "Zeta Capital" on the company page
    And I do not see "ZETA12345P" or "ir@zeta.example" on the company page
