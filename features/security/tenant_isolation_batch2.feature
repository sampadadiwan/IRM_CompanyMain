Feature: Tenant isolation - batch 2 of the 2026-10-17 advisor-role review
  B1 company pages, B3 what a switched advisor's lists show, B4 the smaller isolation fixes.
  Each refusal is paired with the legitimate use that must keep working.
  Worked examples: openspec/changes/fix-tenant-isolation-batch2/report.md#verification

  Background:
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a fund "name=Artha F1" for the entity
    And batch 2 has another tenant "Zeta Capital" with PAN "ZETA12345P" and email "ir@zeta.example"

  # B1-X — Error case: an unrelated user sees only the public profile of another company
  @security @rack_test
  Scenario: B1-X Another company's page shows its name but not its tax id or email
    When I open the entity page of "Zeta Capital"
    Then I see "Zeta Capital" on the company page
    And I do not see "ZETA12345P" or "ir@zeta.example" on the company page

  # B1-H — Happy path: related users still see full details
  @security @rack_test
  Scenario: B1-H Full company details for its own users, its LP contacts and the GP of an LP
    Given "Zeta Capital" is an LP of my fund with an approved contact user
    Then the full details of "Zeta Capital" are shown to me as its GP
    And the full details of my company are shown to the LP contact user
    And the full details of my company are shown to me

  # B3-1 — Error case: a switched advisor's document list shows only documents of funds they were given
  @security @rack_test
  Scenario: B3-1 A switched advisor lists the F1 statement but not the F2 statement or the AGM deck
    Given batch 2 client "Harshal" invests in "Artha F1" and "Artha F2" and has an F1-only advisor
    And Artha shared an F1 statement, an F2 statement and an AGM deck with "Harshal"
    And the advisor has switched into "Harshal"
    Then the advisor's document list for Artha is exactly the F1 statement
    And the advisor can open the F1 statement but not the F2 statement or the AGM deck

  # B3-H — Happy path: the client's own users still see everything shared with them
  @security @rack_test
  Scenario: B3-H A plain user of the client still lists all three documents
    Given batch 2 client "Harshal" invests in "Artha F1" and "Artha F2" and has an F1-only advisor
    And Artha shared an F1 statement, an F2 statement and an AGM deck with "Harshal"
    Then the client's own user lists all three documents

  # B3-2 — Edge case: folders follow the documents the advisor can see
  @security @rack_test
  Scenario: B3-2 A switched advisor does not list a folder holding only documents they cannot see
    Given batch 2 client "Harshal" invests in "Artha F1" and "Artha F2" and has an F1-only advisor
    And Artha shared an F1 statement, an F2 statement and an AGM deck with "Harshal"
    And the advisor has switched into "Harshal"
    Then the advisor's folder list includes the F1 statement's folder but not the AGM folder

  # B3-3 — Error case: approvals and secondary sales follow the advisor's personal grants
  @security @rack_test
  Scenario: B3-3 Approvals and secondary sales shared only with the client are not listed for its advisor
    Given batch 2 client "Harshal" invests in "Artha F1" and "Artha F2" and has an F1-only advisor
    And Artha shared an approval and a secondary sale with "Harshal"
    And the advisor has switched into "Harshal"
    Then the advisor lists neither the approval nor the secondary sale
    And the client's own user lists both the approval and the secondary sale

  # B3-4 — Happy path: a secondary sale granted to the advisor personally is still listed
  @security @rack_test
  Scenario: B3-4 A secondary sale granted to the advisor personally is listed
    Given batch 2 client "Harshal" invests in "Artha F1" and "Artha F2" and has an F1-only advisor
    And Artha shared an approval and a secondary sale with "Harshal"
    And the advisor has a personal grant on the secondary sale for "Harshal"
    And the advisor has switched into "Harshal"
    Then the advisor lists the secondary sale

  # B4-1 — Error case: an LP sees fund-level ratios and their own folio's, not another investor's
  @security @rack_test
  Scenario: B4-1 Fund ratios of another investor's folio are hidden from an LP
    Given the fund shows ratios, with a fund-level ratio and one for each of two LPs' folios
    Then the first LP's user lists the fund-level ratio and their own folio's ratio only
    And the first LP's user cannot open the other LP's folio ratio

  # B4-2 — Error case: a switched advisor cannot edit a client KYC committed only to a fund they were not given
  @security @rack_test
  Scenario: B4-2 A switched advisor cannot edit a client KYC that their grant does not reach
    Given batch 2 client "Harshal" invests in "Artha F1" and "Artha F2" and has an F1-only advisor
    And "Harshal" has a KYC committed only to "Artha F2"
    And the advisor has switched into "Harshal"
    Then the advisor can neither open nor edit that KYC
    And the client's own user can still edit that KYC

  # B4-2-H — Happy path: a switched advisor can fill in a client's onboarding KYC (no commitment yet)
  @security @rack_test
  Scenario: B4-2-H A switched advisor can continue a client KYC that has no commitment yet
    Given batch 2 client "Harshal" invests in "Artha F1" and "Artha F2" and has an F1-only advisor
    And "Harshal" has a KYC with no commitment
    And the advisor has switched into "Harshal"
    Then the advisor can edit that KYC

  # B4-3 — Error case: a DealInvestor needs the advisor's deal grant, as the list does
  @security @rack_test
  Scenario: B4-3 A switched advisor cannot open a client's deal investor without a deal grant
    Given batch 2 client "Harshal" invests in "Artha F1" and "Artha F2" and has an F1-only advisor
    And "Harshal" is a deal investor in a deal of my company
    And the advisor has switched into "Harshal"
    Then the advisor cannot open that deal investor
    And the client's own user can still open that deal investor

  # B4-4 — Error case: staff search results follow the same access as the lists
  @security @rack_test
  Scenario: B4-4 A search result is dropped when the employee cannot see that record in the list
    Given there is a deal in my company that a plain employee has no access to
    Then restricting search results for the plain employee drops that deal
    And restricting search results for me keeps that deal

  # B4-5 — Error case: an MCP token stops working when its user is in another entity
  @security @rack_test
  Scenario: B4-5 An MCP token for one entity is refused while its user is switched into another
    Given the user's entity has MCP enabled
    And the user has an MCP access token
    When the user is moved into "Zeta Capital" without a new token
    And the MCP client posts the JSON-RPC method "tools/list"
    Then the MCP HTTP status should be 401

  # B4-5-H — Happy path: the token works while its user is in the token's entity
  @security @rack_test
  Scenario: B4-5-H An MCP token works while its user is in the token's entity
    Given the user's entity has MCP enabled
    And the user has an MCP access token
    When the MCP client posts the JSON-RPC method "tools/list"
    Then the MCP HTTP status should be 200

  # B4-6 — Error case: a company admin manages only their own entity's validation rules
  @security @rack_test
  Scenario: B4-6 A company admin cannot manage another entity's validation rule
    Given there is a validation rule of "Zeta Capital" and one of my company
    Then I cannot view, update or delete the rule of "Zeta Capital"
    And I can still view and update my company's rule
