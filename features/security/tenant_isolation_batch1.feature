Feature: Tenant isolation - batch 1 of the 2026-10-17 advisor-role review
  Each scenario closes one way a user could act on, or read, another tenant's data, and a paired
  scenario proves the legitimate use of the same screen still works.
  Worked examples: openspec/changes/fix-tenant-isolation-batch1/report.md#verification

  Background:
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a fund "name=Artha Select" for the entity
    And there is another tenant "Zeta Capital" with a fund "Zeta Fund"

  # S1 — Error case: editing a grant cannot move it to another tenant
  @security @rack_test
  Scenario: S1 Editing an advisor grant ignores a changed entity and email
    Given there is an advisor grant in my entity for "adv@advisor.example"
    When I update that grant with entity "Zeta Capital", email "other@x.example" and allowed roles "employee"
    Then the grant still belongs to my entity with email "adv@advisor.example"
    And the grant's allowed roles are "employee"

  # S1-E — Edge case: a grant stays editable after its advisor changed their login email
  @security @rack_test
  Scenario: S1-E A grant whose advisor changed email can still have its roles edited
    Given there is an advisor grant in my entity for "old@advisor.example"
    And that advisor's login email is changed to "new@advisor.example"
    When I update that grant with entity "Artha", email "old@advisor.example" and allowed roles "employee"
    Then the grant's allowed roles are "employee"

  # S2 — Error case: Add Investor Advisor cannot attach another tenant's fund
  @security @rack_test
  Scenario: S2 Adding an investor advisor with another tenant's fund is refused
    Given there is an LP "Harshal" of my fund
    When I add advisor "adv2@advisor.example" for "Harshal" on the fund "Zeta Fund"
    Then I am denied access
    And "adv2@advisor.example" has no access right on the fund "Zeta Fund"

  # S2-H — Happy path: the same form on my own fund still works
  @security @rack_test
  Scenario: S2-H Adding an investor advisor on my own fund still works
    Given there is an LP "Harshal" of my fund
    When I add advisor "adv3@advisor.example" for "Harshal" on the fund "Artha Select"
    Then "adv3@advisor.example" has an access right on the fund "Artha Select"

  # S3 — Error case: a company admin cannot move a user to another tenant
  @security @rack_test
  Scenario: S3 Updating a user ignores a changed entity
    When I update my own user with entity "Zeta Capital" and first name "Gitanjali"
    Then my user is still in my entity with first name "Gitanjali"

  # S4 — Error case: document search stays in the user's own entity
  @security @rack_test
  Scenario: S4 Document search ignores another tenant's entity id
    When I search documents for "contract" passing the entity "Zeta Capital"
    Then the document search ran against my own entity

  # S5 — Error case: an investor cannot edit or delete someone else's unverified offer
  @security @rack_test
  Scenario: S5 An investor cannot edit another seller's unverified offer
    Given there is a secondary sale with an unverified offer by another investor's user
    Then an investor user of a different investor cannot edit, update or delete that offer
    And the offer's own seller can still edit, update and delete it

  # S6 — Error case: fund-wide report pages are for the fund's own staff
  @security @rack_test
  Scenario: S6 An LP of the fund cannot open the fund's report pages
    Given there is an LP user of my fund with access to the fund
    Then the LP user can see the fund but not its reports
    And I can still open the fund's reports

  # S7a — Error case: deal edit needs the update permission, like saving does
  @security @rack_test
  Scenario: S7a Opening a deal's edit page needs the same right as saving it
    Given there is a deal in my entity
    Then a user with only the deals feature cannot open the deal's edit page
    And I can still open the deal's edit page

  # S8 — Error case: the switch confirmation shows an entity name as text
  @security @rack_test
  Scenario: S8 Switching into a client whose name contains markup shows it escaped
    Given I am an advisor with a grant on a client named "Client <b>Bold</b> & Co"
    When I switch into that client
    Then the confirmation shows "Client <b>Bold</b> & Co" as text, not markup

  # R1 — Error case: an import runs in its owner's tenant, whatever entity the form posts
  @security @rack_test
  Scenario: R1 An import posted with another tenant's entity runs in the owner's entity
    When I post an investor import for my fund with entity "Zeta Capital"
    Then the import is saved under my entity

  # R1-U — Error case: updating an import cannot move it to another tenant either
  @security @rack_test
  Scenario: R1-U Updating an import ignores a changed entity
    Given I have an import on my fund
    When I update that import with entity "Zeta Capital"
    Then the import is saved under my entity

  # R1b — Error case: the advisor import's company_admin check is tied to the import's entity
  @security @rack_test
  Scenario: R1b An advisor import granting company_admin is refused when the importer is not in the import's entity
    Then an advisor import into "Zeta Capital" granting "company_admin" by me is refused

  # R1b-H — Happy path: a Fund Advisor's company_admin grant counts even after they switched away
  @security @rack_test
  Scenario: R1b-H An advisor import by a Fund Advisor who has since switched away is not refused for company_admin
    Given there is a Fund Advisor with a company_admin grant on "Zeta Capital" now at home
    Then an advisor import into "Zeta Capital" granting "company_admin" by that Fund Advisor is not refused for the role

  # R2 — Error case: deleting a grant the advisor is switched into sends them home
  @security @rack_test
  Scenario: R2 Deleting a grant while the advisor is switched into it reverts them
    Given there is an advisor switched into a grant on my entity with roles "company_admin"
    When that grant is deleted
    Then the advisor is back in their home entity without the grant's roles

  # R3 — Error case: removing one client keeps no access for that client, even with another client on the fund
  @security @rack_test
  Scenario: R3 Removing an advisor from one client revokes that client's fund grant
    Given an advisor advises clients "C1" and "C2" who are both LPs of my fund
    When the advisor's contact row on "C1" is deleted
    Then the advisor has no access right on my fund for "C1"
    And the advisor still has their access right on my fund for "C2"

  # R4 — Error case: a scheduled report runs against the report's entity, not the owner's current persona
  @security @rack_test
  Scenario: R4 A scheduled report uses the report's entity while its owner is switched elsewhere
    Given there is a report of my entity owned by a Fund Advisor of my entity now switched into "Zeta Capital"
    When the report's schedule runs
    Then the report query ran against my entity

  # R4-X — Error case: a removed owner's schedule stops instead of emailing the company's data
  @security @rack_test
  Scenario: R4-X A scheduled report whose owner no longer belongs to its entity is skipped
    Given there is a report of my entity owned by a Fund Advisor of my entity now switched into "Zeta Capital"
    And that Fund Advisor's grant on my entity is deleted
    When the report's schedule runs
    Then the report query did not run

  # R4-H — Happy path: an on-demand export is unchanged
  @security @rack_test
  Scenario: R4-H An on-demand report export still uses the requesting user's entity
    Given there is a report of my entity owned by me
    When I export the report on demand
    Then the report query ran against my entity

  # R5 — Error case: a client's admin cannot edit an advisor who is switched into the client
  @security @rack_test
  Scenario: R5 A client's company admin cannot edit or reset an advisor switched into their company
    Given there is an advisor from "Advisory Co" switched into my entity
    Then I cannot view, edit or reset two-factor for that advisor
    And the advisor can still edit themselves
    And a company admin of "Advisory Co" can still edit the advisor

  # R7 — Error case: a switch that fails part-way leaves the user where they were
  @security @rack_test
  Scenario: R7 A switch whose role update fails does not move the user's entity
    Given there is an advisor at home with a grant on my entity
    When the advisor's switch fails while adding roles
    Then the advisor is still in their home entity with their home roles

  # R7-X — Error case: a switch into a grant deleted meanwhile is refused
  @security @rack_test
  Scenario: R7-X Switching into a grant that was deleted meanwhile is refused
    Given there is an advisor at home with a grant on my entity
    When the grant is deleted and the advisor then switches using the copy loaded before
    Then the switch is refused and the advisor is still in their home entity with their home roles
