Feature: Secondaries isolation - 2026-10 security review
  Buyers, sellers, RMs and the selling company's own staff each see only their side of a secondary
  sale. Each scenario closes one way a party could reach another party's PII (PAN, bank details,
  holdings) or act on records that are not theirs, and is paired with the legitimate use of the
  same screen that must keep working.
  Design and worked examples: docs/security/security_review_2026_10.md (C4 and the other secondaries
  cards).

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
    And the user has role "company_admin"
    And there is a sale "name=Grand Sale"
    And the sale has a seller with an approved offer and a buyer with a short-listed interest

  # C4-1 — Edge case: a buyer cannot render the sale's full-PII download sheet through the old report address
  @security @rack_test
  Scenario: C4-1 A buyer opening the sale report with report=download gets a 404
    When the sale's "buyer" opens the sale's report address with report "download"
    Then the address is not found
    And no seller or buyer PAN or bank account is in the response

  # C4-2 — Edge case: a seller cannot render the sale's payments sheet through the old report address
  @security @rack_test
  Scenario: C4-2 A seller opening the sale report with report=payments gets a 404
    When the sale's "seller" opens the sale's report address with report "payments"
    Then the address is not found
    And no seller or buyer PAN or bank account is in the response

  # C4-H — Happy path: the sale's company admin still opens the Offers Completion Report
  @security @rack_test
  Scenario: C4-H The sale's company admin opens the Offers Completion Report
    Then the offers completetion page must be visible

  # C4-X — Edge case: the owner-only sale download stays refused to a seller (regression guard)
  @security @rack_test
  Scenario: C4-X A seller downloading the sale sheet as xlsx is refused
    When the sale's "seller" downloads the sale sheet as xlsx
    Then I am denied access
    And no seller or buyer PAN or bank account is in the response

  # ---- H11 — Allocations list + PII Ransack ----------------------------------------------------
  # Parties are named by a letter: "A->B" is an allocation of seller A's offer to buyer B's interest.
  # Each party is its own LP firm with a signed-up user, an approved investor access and a sale grant.

  # H11-1 — Edge case: a seller's All Allocations lists only the allocations of their own offers
  @security @rack_test
  Scenario: H11-1 A seller lists only the allocations of their own offers
    Given the sale has allocations "A->B, C->D"
    When "A" lists the sale's allocations
    Then the allocations listed are "A->B"

  # H11-2 — Edge case: a buyer filtering by a seller's PAN learns nothing - the condition is ignored
  @security @rack_test
  Scenario: H11-2 A buyer filtering allocations by a seller's PAN has the condition ignored
    Given the sale has allocations "A->B, C->D"
    When "B" lists the sale's allocations filtered by "offer_PAN_eq" "WRONG0000X"
    Then the allocations listed are "A->B"

  # H11-3 — Edge case: a seller filtering by a buyer's email learns nothing - the condition is ignored
  @security @rack_test
  Scenario: H11-3 A seller filtering allocations by a buyer's email has the condition ignored
    Given the sale has allocations "A->B, C->D"
    When "A" lists the sale's allocations filtered by "interest_email_eq" "nobody@nowhere.example"
    Then the allocations listed are "A->B"

  # H11-4 — Edge case: another firm's sale in the allocations list is refused and its name is not shown
  @security @rack_test
  Scenario: H11-4 An LP listing the allocations of another firm's sale is refused
    Given the sale has allocations "A->B"
    And another firm "Zeta Capital" has a sale "Zeta Secret Sale"
    When "A" lists the allocations of the sale "Zeta Secret Sale"
    Then I am denied access
    And "Zeta Secret Sale" is not in the response

  # H11-H — Happy path: the sale's company admin lists every allocation, and sorting by offer still works
  @security @rack_test
  Scenario: H11-H The sale's company admin lists all allocations sorted by offer name
    Given the sale has allocations "C->D, A->B"
    When the sale's company admin lists the sale's allocations sorted by "offer_full_name asc"
    Then the allocations listed in order are "A->B, C->D"

  # H11-X — Edge case: an LP who both sold and bought lists the rows of both sides, and only those
  @security @rack_test
  Scenario: H11-X An LP who is both seller and buyer lists both sides of their own allocations
    Given the sale has allocations "A->B, E->B, C->E, C->D"
    When "E" lists the sale's allocations
    Then the allocations listed are "E->B, C->E"

  # H11-X2 — Edge case: a seller on the holding persona is limited to their own rows as well
  @security @rack_test
  Scenario: H11-X2 A holding-persona seller can list only their own allocations
    Given the sale has allocations "H->B, C->D"
    And "H" uses the holding persona
    Then the allocations "H" can list are "H->B"

  # ---- H15 — RM sale actions and template ids ------------------------------------------------

  # H15-1 — Edge case: an RM with no access to another firm's sale cannot regenerate its SPAs
  @security @rack_test
  Scenario: H15-1 An RM without access regenerating another firm's sale SPAs is refused
    Given another firm "Zeta Capital" has a sale "Zeta Secret Sale"
    And there is an RM "Rex" with no access to the sale "Zeta Secret Sale"
    When the RM "Rex" asks to regenerate the offer SPAs of the sale "Zeta Secret Sale"
    Then I am denied access
    And no SPA generation was queued

  # H15-2 — Edge case: an RM with no access to another firm's sale cannot import into it
  @security @rack_test
  Scenario: H15-2 An RM without access cannot upload interests or offers into another firm's sale
    Given another firm "Zeta Capital" has a sale "Zeta Secret Sale"
    And there is an RM "Rex" with no access to the sale "Zeta Secret Sale"
    Then the RM "Rex" may not upload interests or offers into the sale "Zeta Secret Sale"

  # H15-3 — Edge case: another firm's template id finds no template, and this offer's SPA is kept
  @security @rack_test
  Scenario: H15-3 Generating an offer document with another firm's template finds no template
    Given the sale has a SPA template
    And the seller's offer already has a generated "SPA"
    And another firm "Zeta Capital" has a sale "Zeta Secret Sale" with an offer SPA template
    When the documents of the seller's offer are generated with the template of the sale "Zeta Secret Sale"
    Then the generation reports "No templates found"
    And no document was rendered
    And the seller's offer still has its generated "SPA"

  # H15-4 — Edge case: another sale's template id - even in my own firm - finds no template either
  @security @rack_test
  Scenario: H15-4 Generating an offer document with another sale's template finds no template
    Given the sale has a SPA template
    And the seller's offer already has a generated "SPA"
    And my firm has another sale "Other Sale" with an offer SPA template
    When the documents of the seller's offer are generated with the template of the sale "Other Sale"
    Then the generation reports "No templates found"
    And no document was rendered
    And the seller's offer still has its generated "SPA"

  # H15-H — Happy path: the sale's own template still renders for the sale's offer
  @security @rack_test
  Scenario: H15-H The sale's own template is rendered for its offer
    Given the sale has a SPA template
    When the documents of the seller's offer are generated with the sale's own template
    Then the sale's own template was rendered for the seller's offer

  # H15-H2 — Happy path: an RM with access to a live sale may still upload interests
  @security @rack_test
  Scenario: H15-H2 An RM with access may upload interests but not regenerate SPAs or upload offers
    Given there is an RM "Rex" with access to the sale
    Then the RM "Rex" may upload interests into the sale
    And the RM "Rex" may not regenerate the sale's SPAs or upload offers into it

  # H15-X — Edge case: once the sale has closed, the RM can neither regenerate SPAs nor upload interests
  @security @rack_test
  Scenario: H15-X An RM with access to a closed sale may neither regenerate SPAs nor upload interests
    Given there is an RM "Rex" with access to the sale
    And the sale has closed
    Then the RM "Rex" may neither regenerate the sale's SPAs nor upload interests into it

  # ---- H19 — LP workflow flags (offers, interests) -------------------------------------------

  # H19-1 — Edge case: a seller's own offer ignores the workflow flags they send, and queues no SPA
  @security @rack_test
  Scenario: H19-1 A seller sending verified and allocation flags on their own offer has them dropped
    Given "X" has an unverified offer on the sale
    When "X" updates their offer with "quantity=12;verified=1;allocation_quantity=7" and points it at the buyer's interest
    Then the offer of "X" has "quantity=12;verified=false;allocation_quantity=0;interest_id="
    And no SPA generation was queued

  # H19-2 — Edge case: a buyer's own interest ignores the workflow flags they send
  @security @rack_test
  Scenario: H19-2 A buyer sending verified, escrow and final-agreement flags on their own interest has them dropped
    Given "Y" has an unverified interest on the sale
    When "Y" updates their interest with "quantity=12;verified=1;final_agreement=1;escrow_deposited=1;allocation_quantity=7"
    Then the interest of "Y" has "quantity=12;verified=false;final_agreement=false;escrow_deposited=false;allocation_quantity=0"

  # H19-3 — Edge case: a buyer cannot create an offer in the name of another investor
  @security @rack_test
  Scenario: H19-3 A buyer creating an offer for another investor is refused
    Given "X" has an unverified offer on the sale
    And "Y" has an unverified interest on the sale
    When "Y" creates an offer on the sale for the investor of "X"
    Then I am denied access
    And the investor of "X" has 1 offer on the sale

  # H19-H — Happy path: a seller still edits the PAN and bank details of their own unverified offer
  @security @rack_test
  Scenario: H19-H A seller edits the PAN and bank details of their own offer
    Given "X" has an unverified offer on the sale
    When "X" updates their offer with "PAN=XPAN98765Q;bank_account_number=123456789012;ifsc_code=HDFC0001234"
    Then the offer of "X" has "PAN=XPAN98765Q;bank_account_number=123456789012;ifsc_code=HDFC0001234"

  # H19-H2 — Happy path: the sale's company admin still ticks escrow deposited on an interest
  @security @rack_test
  Scenario: H19-H2 The sale's company admin ticks escrow deposited on an interest
    Given "Y" has an unverified interest on the sale
    And the sale lets its firm manage interests
    When the sale's company admin updates the interest of "Y" with "escrow_deposited=1"
    Then the interest of "Y" has "escrow_deposited=true"

  # H19-X — Edge case: another firm's company admin cannot verify an offer of this sale
  @security @rack_test
  Scenario: H19-X Another firm's company admin setting verified on an offer is refused
    Given "X" has an unverified offer on the sale
    And I am signed in as a company admin of another firm "Zeta Capital"
    When I update the offer of "X" with "verified=1"
    Then I am denied access
    And the offer of "X" has "verified=false"

  # ---- M10 — offers / interests report names (secondaries part) ------------------------------

  # M10-S1 — Edge case: a report name the sale page does not link to is a 404 on the offers list, not a render of that template
  @security @rack_test
  Scenario: M10-S1 The offers list with an unlisted report name is not found
    When the sale's company admin opens the sale's "offers" with report "edit"
    Then the address is not found

  # M10-S2 — Edge case: a path-like report name on the interests list cannot reach the sale's PII download sheet
  @security @rack_test
  Scenario: M10-S2 The interests list with a path-like report name is not found and shows no PAN
    When the sale's company admin opens the sale's "interests" with report "../secondary_sales/download"
    Then the address is not found
    And no seller or buyer PAN or bank account is in the response

  # M10-SH — Happy path: the Interests Completion Report the sale's Reports menu links to still renders
  @security @rack_test
  Scenario: M10-SH The sale's company admin opens the Interests Completion Report
    When the sale's company admin opens the sale's "interests" with report "completion_report"
    Then the response mentions "Interest Completion Report"

  # ---- SL — sale lookups through the user's scope (flagged after H11) ------------------------

  # SL-1 — Edge case: another firm's sale id on the interests list is refused and its name is not shown
  @security @rack_test
  Scenario: SL-1 A buyer listing the interests of another firm's sale is refused
    Given another firm "Zeta Capital" has a sale "Zeta Secret Sale"
    When the sale's "buyer" lists the interests of the sale "Zeta Secret Sale"
    Then I am denied access
    And "Zeta Secret Sale" is not in the response

  # SL-2 — Edge case: another firm's sale id on the offers list is refused and its name is not shown
  @security @rack_test
  Scenario: SL-2 A seller listing the offers of another firm's sale is refused
    Given another firm "Zeta Capital" has a sale "Zeta Secret Sale"
    When the sale's "seller" lists the offers of the sale "Zeta Secret Sale"
    Then I am denied access
    And "Zeta Secret Sale" is not in the response

  # SL-3 — Edge case: the offers search with another firm's sale id is refused before any search runs
  @security @rack_test
  Scenario: SL-3 A seller searching the offers of another firm's sale is refused
    Given another firm "Zeta Capital" has a sale "Zeta Secret Sale"
    When the sale's "seller" searches the offers of the sale "Zeta Secret Sale" for "Seller"
    Then I am denied access
    And "Zeta Secret Sale" is not in the response

  # SL-H — Happy path: a buyer still lists the interests of their own sale, with the sale in the breadcrumb
  @security @rack_test
  Scenario: SL-H A buyer lists the interests of their own sale
    When the sale's "buyer" lists the interests of the sale
    Then the response mentions "Grand Sale"

  # ---- M11 — allocation create and update ----------------------------------------------------

  # M11-1 — Edge case: another firm's company admin, naming their own sale, cannot build an allocation into this sale from its offer and interest
  @security @rack_test
  Scenario: M11-1 Another firm's company admin creating an allocation from this sale's offer is refused
    Given "A" has an unverified offer on the sale
    And "B" has an unverified interest on the sale
    And I am signed in as a company admin of another firm "Zeta Capital"
    And another firm "Zeta Capital" has a sale "Zeta Sale"
    When I create an allocation of 2 shares from the offer of "A" to the interest of "B" naming the sale "Zeta Sale"
    Then I am denied access
    And there is no allocation from the offer of "A" to the interest of "B"

  # M11-2 — Edge case: an update cannot move an allocation to another offer, interest or firm
  @security @rack_test
  Scenario: M11-2 Updating an allocation's offer, interest and firm leaves them unchanged
    Given the sale has allocations "A->B, C->D"
    When the sale's company admin updates the allocation "A->B" with the offer of "C", the interest of "D" and the notes "moved"
    Then the allocation "A->B" is still from the offer of "A" to the interest of "B" with the notes "moved"

  # M11-H — Happy path: the sale's company admin still creates an allocation by hand
  @security @rack_test
  Scenario: M11-H The sale's company admin creates an allocation from a seller's offer and a buyer's interest
    Given "A" has an unverified offer on the sale
    And "B" has an unverified interest on the sale
    When the sale's company admin creates an allocation of 2 shares from the offer of "A" to the interest of "B"
    Then the sale has an allocation of 2 shares from the offer of "A" to the interest of "B"
