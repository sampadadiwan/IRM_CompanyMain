Feature: EOI workflow flags - 2026-10 security review (H19)
  An investor fills in their own expression of interest - amount, KYC, details - but approving it,
  verifying it, opening the Data Room and allocating it are the opportunity firm's decisions. Each
  scenario closes one way an investor could set those flags on their own EOI, and is paired with the
  firm's legitimate use of the same screen.
  Design and worked examples: docs/security/security_review_2026_10.md (card "H19 — LP workflow flags").

  Background:
    Given Im logged in as a user "first_name=Ira" for an entity "name=Artha;entity_type=Investment Fund;enable_inv_opportunities=true"
    And the user has role "company_admin"
    And there is an investment_opportunity "company_name=Alpha IO"
    And there is an LP "Patel Family" of the opportunity with a signed-up user
    And the LP has an unapproved EOI on the opportunity

  # H19-4 — Edge case: the investor's own EOI ignores the approval, allocation and Data Room flags they send
  @security @rack_test
  Scenario: H19-4 An investor updating their own EOI has the workflow flags dropped
    When the LP updates their EOI with "amount=3000000;approved=1;verified=1;show_data_room=1;allocation_amount=1500000"
    Then the EOI has "amount=3000000;approved=false;verified=false;show_data_room=false;allocation_amount=0"
    And the LP may still edit their EOI but is not offered the Data Room toggle

  # H19-5 — Edge case: the investor cannot allocate their own EOI
  @security @rack_test
  Scenario: H19-5 An investor allocating their own EOI is refused
    When the LP allocates their EOI with "allocation_amount=1500000;verified=1;comment=Self allocated"
    Then I am denied access
    And the EOI has "allocation_amount=0;verified=false"
    And the LP may not open the allocation form of their EOI

  # H19-H3 — Happy path: the opportunity's company admin allocates the EOI
  @security @rack_test
  Scenario: H19-H3 The opportunity's company admin allocates an EOI
    When I allocate the EOI with "allocation_amount=1500000;verified=1;approved=0;comment=Allocated"
    Then the EOI has "allocation_amount=1500000;verified=true;comment=Allocated"

  # H19-A1 — Edge case: an LP-side user holding the approver role cannot approve their own EOI
  @security @rack_test
  Scenario: H19-A1 An LP approver approving their own EOI is refused
    Given the LP's user has the approver role
    When the LP approves their EOI
    Then I am denied access
    And the EOI has "approved=false"
    And the LP may not approve their EOI

  # H19-AH — Happy path: an approver of the opportunity's firm approves the EOI
  @security @rack_test
  Scenario: H19-AH The opportunity firm's approver approves an EOI
    Given the user has role "approver"
    When I approve the EOI
    Then the EOI has "approved=true"
