Feature: Compliance — tenant isolation and maker–checker
  Other firms, viewers, investors and direct requests are refused; approvers never approve their own requests.
  Worked examples: openspec/changes/fund-compliance-monitoring/business-rules.md

  Background:
    Given the Horizon compliance setup
    And Delta Partners with a company admin "Dev" and a fund "Delta Fund"
    And an investor user "Lata" in Growth Fund I

  # X11 — Error case: Priya cannot test-run on Delta without its support access
  @security @rack_test
  Scenario: X11 Test run without consent
    Given Priya is a CapHive content admin
    And I am signed in to compliance as "Priya"
    When I request a test run of the SEBI pack on "Delta Fund"
    Then the compliance request is denied

  # X12 — Error case: Dev does not see Horizon's entity pack, and opening it by URL is refused
  @security @rack_test
  Scenario: X12 Other firm reads entity pack
    Given I am signed in to compliance as "Dev"
    When I open the compliance packs list
    Then the compliance page does not show "Horizon — fund agreement limits"
    When I open the Horizon fund agreement pack by URL
    Then the compliance request is denied

  # X13 — Error case: Meera cannot edit the CapHive SEBI pack by a direct request
  @security @rack_test
  Scenario: X13 Customer edits CapHive pack
    Given I am signed in to compliance as "Meera"
    When I send an edit of the SEBI pack setting the concentration limit to 30
    Then the compliance request is denied
    And the SEBI concentration limit is still 25

  # X18 — Error case: Meera cannot approve her own override (button and direct request)
  @security @rack_test
  Scenario: X18 Self-approval
    Given "Meera" has a pending override of "Single-investee concentration" on "Horizon Growth Fund I" at 20
    And I am signed in to compliance as "Meera"
    When I approve the latest compliance request
    Then the compliance page shows "Another approver must approve your request"
    And the latest compliance request is still "pending"

  # X19 — Error case: Vikram (viewer) cannot attach a pack by a direct request
  @security @rack_test
  Scenario: X19 Viewer changes setup
    Given I am signed in to compliance as "Vikram"
    When I attach "Horizon — fund agreement limits" to "Horizon Growth Fund I" by a direct request
    Then the compliance request is denied
    And "Horizon Growth Fund I" carries no "Horizon — fund agreement limits"

  # X20 — Error case: Vikram has no GIFT access — GIFT items are hidden and refused by URL
  @security @rack_test
  Scenario: X20 No fund access
    Given "Horizon GIFT Opportunities" also carries the fund agreement pack
    And the fund agreement concentration on "Horizon GIFT Opportunities" has an open item
    And I am signed in to compliance as "Vikram"
    When I open the compliance register
    Then the compliance page does not show "Horizon GIFT Opportunities"
    When I open the GIFT register item by URL
    Then the compliance request is denied

  # X21 — Error case: Dev (Delta) cannot open Horizon's setup or a Horizon item by id
  @security @rack_test
  Scenario: X21 Other firm
    Given the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Dev"
    When I open a Horizon register item by URL
    Then the compliance request is denied
    When I open the compliance setup
    Then the compliance page does not show "Horizon"

  # X22 — Error case: Lata (investor) is refused on every Compliance URL and has no menu entry
  @security @rack_test
  Scenario: X22 Investor
    Given I am signed in to compliance as "Lata"
    When I open the compliance home
    Then the compliance request is denied
    And Lata has no Compliance menu entry

  # X23 — Error case: an attach request carrying Delta's fund id is refused and creates nothing
  @security @rack_test
  Scenario: X23 Foreign fund id smuggled
    Given I am signed in to compliance as "Meera"
    When I attach "SEBI — AIF" to "Delta Fund" by a direct request
    Then the compliance request is denied
    And "Delta Fund" carries no "SEBI — AIF"

  # X30 — Error case: Meera wrote the explanation and cannot approve it
  @security @rack_test
  Scenario: X30 Author approves own explanation
    Given the nightly compliance run happens on "2026-11-05"
    And "Meera" explains the "Single-investee concentration" item with "Exit of Acme agreed for Q4"
    And I am signed in to compliance as "Meera"
    When I approve the latest compliance request
    Then the compliance page shows "Another approver must approve your request"
    And the latest compliance request is still "pending"

  # X34 — Error case: Vikram (viewer) cannot mark a duty done by a direct request
  @security @rack_test
  Scenario: X34 Viewer marks duty done
    Given the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Vikram"
    When I mark the "Quarterly SEBI report filed" duty done by a direct request
    Then the compliance request is denied

  # X35 — Error case: compliance events never notify the investor or advisors
  @security @rack_test
  Scenario: X35 Investor never notified
    Given the nightly compliance run happens on "2026-11-05"
    And "Meera" assigns the "Single-investee concentration" item to "Arjun"
    And "Meera" explains the "Single-investee concentration" item with "Exit of Acme agreed for Q4"
    And the compliance digest is sent on "2026-11-05"
    Then "Lata" got no compliance notices

  # X36 — Error case: Dev and Lata cannot export Horizon's register
  @security @rack_test
  Scenario: X36 Export by another user
    Given the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Lata"
    When I export the compliance register for November 2026
    Then the compliance request is denied

  # X54 — Error case: an override of the not-overridable "Investors in scheme" is refused by a direct request
  @security @rack_test
  Scenario: X54 Not-overridable, direct
    Given I am signed in to compliance as "Meera"
    When I request an override of "Investors in scheme" to 2000 by a direct request
    Then the compliance page shows "This check cannot be overridden"
    And no compliance request was created

  # X55 — Error case: a company admin sending limit 30 to the locked SEBI pack is refused; unchanged
  @security @rack_test
  Scenario: X55 Edit locked pack, direct
    Given I am signed in to compliance as "Anil"
    When I send an edit of the SEBI pack setting the concentration limit to 30
    Then the compliance request is denied
    And the SEBI concentration limit is still 25

  # X57 — Error case: Meera cannot approve her own early adoption
  @security @rack_test
  Scenario: X57 Early adoption self-approval
    Given SEBI v2 allowing early adoption is published on "2026-12-01" effective "2027-01-01" for "all" funds
    And "Meera" requests early adoption of SEBI v2 for "Horizon Growth Fund I" on "2026-12-10"
    And I am signed in to compliance as "Meera"
    When I approve the latest compliance request
    Then the compliance page shows "Another approver must approve your request"
    And the latest compliance request is still "pending"

  # X60 — Error case: attaching a retired pack by a direct request is refused
  @security @rack_test
  Scenario: X60 Attach retired, direct
    Given the SEBI pack is retired on "2026-11-01"
    And I am signed in to compliance as "Meera"
    When I attach "SEBI — AIF" to "Horizon Seed Fund" by a direct request
    Then the compliance page shows "SEBI — AIF is retired"
    And "Horizon Seed Fund" carries no "SEBI — AIF"

  # X61 — Error case: Dev cannot open Growth Fund I's version preview
  @security @rack_test
  Scenario: X61 Preview by other firm
    Given SEBI v2 is published on "2026-12-01" effective "2027-01-01" for "all" funds
    And I am signed in to compliance as "Dev"
    When I open the Growth Fund I preview of SEBI v2 by URL
    Then the compliance request is denied

  # X64 — Error case: Meera cannot approve her own classification change (Horizon has two eligible users)
  @security @rack_test
  Scenario: X64 Classification self-approval
    Given "Meera" requests to classify "Horizon Growth Fund I" as "Category II — LVF" under SEBI
    And I am signed in to compliance as "Meera"
    When I approve the latest compliance request
    Then the compliance page shows "Another approver must approve your request"
    And the latest compliance request is still "pending"

  # X65 — Error case: a direct request to re-run 05 Nov is refused; 05 Nov results unchanged
  @security @rack_test
  Scenario: X65 Re-run a past date
    Given the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I request a re-run of "Horizon Growth Fund I" for "2026-11-05"
    Then the compliance request is denied
    And "Horizon Growth Fund I" has 1 compliance run on "2026-11-05"

  # X66 — Error case: a direct request to delete a stored result is refused
  @security @rack_test
  Scenario: X66 Delete a result
    Given the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I request deletion of the latest Growth Fund I result
    Then the compliance request is denied
    And the latest Growth Fund I result still exists
