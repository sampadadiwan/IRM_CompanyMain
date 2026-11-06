Feature: Compliance screens — filter, lazy tabs, Turbo streams and the explained working
  The register filter and its tabs agree, tabs load lazily like the fund page, row actions answer with
  Turbo streams, and every result page explains its working. Worked examples:
  openspec/changes/fund-compliance-monitoring/business-rules.md (group 12)

  Background:
    Given the Horizon compliance setup

  # E139 — Edge case: filtering the register by status = closed and by fund narrows the rows and the cards; a status condition replaces the tabs
  @rack_test
  Scenario: E139 Register filter and status tabs agree
    Given Horizon also has a fund "Horizon Credit Fund" with a closed register item
    When the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I open the register tab "open"
    Then the register grid lists 2 items
    And the register card "Open" shows 2
    When I filter the register frame by status "closed" and fund "Horizon Credit Fund"
    Then the register grid lists 1 item
    And the register card "Open" shows 0
    When I open the register page filtered by status "closed"
    Then the register shows only the "Filter results" tab

  # E143 — Edge case: register, version and fund-pack tabs are lazy pills; a non-default tab loads its own content
  @rack_test
  Scenario: E143 Tabs load lazily
    When the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I open the compliance register
    Then the tab "register_closed_frame" loads lazily
    When I open the register tab "closed"
    Then the compliance page shows "No register items here"
    When I open the SEBI version page
    Then the tab "version_duties_pane" loads lazily
    When I open the "duties" tab of the SEBI version
    Then the compliance page shows "Quarterly SEBI report filed"
    When I open the Growth Fund I SEBI dashboard
    Then the SEBI results tab loads lazily
    When I open the SEBI results tab of Growth Fund I
    Then the compliance page shows "Single-investee concentration"

  # E140 — Edge case: assign, request, approve, duty done, confirm facts, mark signed and Run now answer with Turbo streams that replace the row or summary and show the flash
  @rack_test
  Scenario: E140 Row actions answer with Turbo streams
    Given Horizon checks IC note contents on "Horizon Growth Fund I"
    And "Horizon Growth Fund I" invested ₹18.0 cr in "Orbit Health" on "2026-10-05"
    And AI reading is on for the "IC note" input
    And the document AI reads the Orbit Health IC note
    When "Arjun" uploads the IC note of "Orbit Health"
    And the documents are read
    And the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I assign the "Single-investee concentration" item to "Arjun" as a Turbo stream
    Then the Turbo stream replaces the "Single-investee concentration" item
    When I request an explanation of the "Single-investee concentration" item as a Turbo stream
    Then the Turbo stream replaces the "Single-investee concentration" item
    When I mark the "Quarterly SEBI report filed" duty done as a Turbo stream
    Then the Turbo stream replaces the "Quarterly SEBI report filed" duty row
    When I confirm the facts of the IC note of "Orbit Health" as a Turbo stream
    Then the Turbo stream replaces the facts of the IC note of "Orbit Health"
    When I run "Horizon Growth Fund I" now as a Turbo stream
    Then the Turbo stream shows the flash "Running"
    Given I am signed in to compliance as "Rahul"
    When I approve the explanation of the "Single-investee concentration" item as a Turbo stream
    Then the Turbo stream replaces the "Single-investee concentration" item

  # E141 — Edge case: the concentration result explains itself — Acme ₹72.00 cr ÷ ₹270.00 cr = 26.67% > 25%; reduce Acme to ₹67.50 cr (₹4.50 cr less) or raise investable funds to ₹288.00 cr
  @rack_test
  Scenario: E141 Concentration working explained
    When the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I open the latest "Single-investee concentration" result of "Horizon Growth Fund I"
    Then the result verdict says "26.67% of investable funds — above the"
    And the result steps include "Investable funds" = "₹270.00 cr"
    And the result steps include "Corpus" = "₹300.00 cr"
    And the result remedy says reduce to "₹67.50 cr" by "₹4.50 cr" or raise to "₹288.00 cr"
    And the result lists the largest investees

  # E142 — Edge case: document, could-not-check and passing limit results read the same way — a verdict, then the records or what is missing, or the headroom
  @rack_test
  Scenario: E142 Every check kind has a verdict
    Given "Horizon Growth Fund I" also carries the fund agreement pack
    And "Horizon Growth Fund I" invested in "Acme B2" on "2026-09-12" with no IC note
    And the estimated expenses of "Horizon Growth Fund I" are blank
    When the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I open the latest "IC note for every investment" result of "Horizon Growth Fund I"
    Then the result verdict says "records are missing a signed document"
    And the compliance page shows "Records that fail"
    When I open the latest "Single-investee concentration" result of "Horizon Growth Fund I"
    Then the result verdict says "Could not check — missing: estimated expenses"
    And the compliance page shows "Fix it in Setup"
    When I open the latest "Investors in scheme" result of "Horizon Growth Fund I"
    Then the result verdict says "within the"

  # E144 — Edge case: continuing interest (amount) shows its limit worked out — 2.5% of Corpus ₹7.50 cr, fixed ₹5.00 cr, the lower ₹5.00 cr — sponsor ₹6.00 cr passes with ₹1.00 cr headroom; no step restates its own value
  @rack_test
  Scenario: E144 Limit worked out from the fund's figures
    When the nightly compliance run happens on "2026-11-05"
    And I am signed in to compliance as "Meera"
    When I open the latest "Continuing interest — amount" result of "Horizon Growth Fund I"
    Then the result steps include "Sponsor/manager commitment" = "₹6.00 cr"
    And the result steps include "2.5% of Corpus" = "₹7.50 cr"
    And the result steps include "Fixed amount" = "₹5.00 cr"
    And the result steps include "Required continuing interest" = "₹5.00 cr"
    And the compliance page shows "₹1.00 cr above the limit"
    And no result step restates its own value
