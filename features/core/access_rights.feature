@unit
Feature: Access Rights - Policy and Scope Enforcement
  The access control system has two enforcement layers:
    1. Scope (list pages): for_employee and for_investor JOINs filter what records appear
    2. Policy (single record): Pundit permissioned_employee/investor checks allow/deny CRUD

  For investors, access requires BOTH an AccessRight AND an approved InvestorAccess.
  For employees, access requires only an AccessRight.

  Background:
    # entity_type=Investment Fund is required so entity.is_fund? returns true,
    # which the scope resolver checks before routing to for_employee/for_company_admin.
    Given there is an entity "name=Fund Entity;entity_type=Investment Fund"
    And there is a fund "name=Main Fund" for the entity "name=Fund Entity"
    # entity_type=Investor prevents setup_defaults from adding unexpected roles (e.g. :investor_advisor)
    And there is an entity "name=Investor Firm;entity_type=Investor"
    # The advisor's own firm, kept separate from Investor Firm above because the two need
    # opposite entity types: an advisor's home entity MUST be Investor Advisor so that
    # setup_defaults records advisor_entity_id (see the Investor Advisor section below), while
    # the LP's entity must not be, so its users are not handed the investor_advisor role.
    # Creating a user here also adds that role via setup_defaults; the scenarios still state it
    # explicitly so the requirement is visible in the scenario itself.
    And there is an entity "name=Advisor Firm;entity_type=Investor Advisor"
    And there is an investor "investor_name=Big LP" for the entity "name=Fund Entity" with investor_entity "name=Investor Firm"

  # ---------------------------------------------------------------------------
  # Employee Policy
  # ---------------------------------------------------------------------------

  Scenario: Employee without an access right cannot see the fund
    Given there is a user "email=emp@example.com" for the entity "name=Fund Entity"
    And the user "emp@example.com" has role "employee"
    Then the user "emp@example.com" should be denied "show,update,destroy" on the fund

  Scenario: Employee with read-only access right can show but not mutate
    Given there is a user "email=emp@example.com" for the entity "name=Fund Entity"
    And the user "emp@example.com" has role "employee"
    When I grant "read" access to the fund for user "emp@example.com"
    Then the user "emp@example.com" should be allowed "show" on the fund
    And the user "emp@example.com" should be denied "update,destroy" on the fund

  Scenario: Employee with full CRUD access right can show and mutate
    Given there is a user "email=emp@example.com" for the entity "name=Fund Entity"
    And the user "emp@example.com" has role "employee"
    When I grant "create,read,update,destroy" access to the fund for user "emp@example.com"
    Then the user "emp@example.com" should be allowed "show,update,destroy" on the fund

  Scenario: Company admin sees the fund without any access right
    Given there is a user "email=admin@example.com" for the entity "name=Fund Entity"
    And the user "admin@example.com" has role "company_admin"
    Then the user "admin@example.com" should be allowed "show,update,destroy" on the fund

  # ---------------------------------------------------------------------------
  # Employee Scope (for_employee)
  # ---------------------------------------------------------------------------

  Scenario: Employee scope returns only explicitly granted funds, not all entity funds
    Given there is a user "email=emp@example.com" for the entity "name=Fund Entity"
    And the user "emp@example.com" has role "employee"
    And there is a fund "name=Second Fund" for the entity "name=Fund Entity"
    When I grant "read" access to "Main Fund" for user "emp@example.com"
    Then the fund scope for user "emp@example.com" should include "Main Fund"
    And the fund scope for user "emp@example.com" should not include "Second Fund"

  Scenario: Company admin scope returns all entity funds without access rights
    Given there is a user "email=admin@example.com" for the entity "name=Fund Entity"
    And the user "admin@example.com" has role "company_admin"
    And there is a fund "name=Second Fund" for the entity "name=Fund Entity"
    Then the fund scope for user "admin@example.com" should include "Main Fund"
    And the fund scope for user "admin@example.com" should include "Second Fund"

  # ---------------------------------------------------------------------------
  # Investor Policy - two-gate check (AccessRight AND approved InvestorAccess)
  # ---------------------------------------------------------------------------

  Scenario: Investor with access right but no InvestorAccess cannot access fund
    Given there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    And I grant "read" access to the fund for investor "Big LP"
    Then the user "lp@example.com" should be denied "show" on the fund

  Scenario: Investor with unapproved InvestorAccess and access right cannot access fund
    Given there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    And I grant "read" access to the fund for investor "Big LP"
    And there is an unapproved investor access for "lp@example.com" and investor "Big LP"
    Then the user "lp@example.com" should be denied "show" on the fund

  Scenario: Investor with approved InvestorAccess and access right can access fund
    Given there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    And I grant "read" access to the fund for investor "Big LP"
    And there is an approved investor access for "lp@example.com" and investor "Big LP"
    Then the user "lp@example.com" should be allowed "show" on the fund
    And the user "lp@example.com" should be denied "update,destroy" on the fund

  Scenario: Investor with approved InvestorAccess but no access right cannot access fund
    Given there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    And there is an approved investor access for "lp@example.com" and investor "Big LP"
    Then the user "lp@example.com" should be denied "show" on the fund

  Scenario: Investor loses access when InvestorAccess is unapproved
    Given there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    And I grant "read" access to the fund for investor "Big LP"
    And there is an approved investor access for "lp@example.com" and investor "Big LP"
    Then the user "lp@example.com" should be allowed "show" on the fund
    When I unapprove the investor access for "lp@example.com"
    Then the user "lp@example.com" should be denied "show" on the fund

  # ---------------------------------------------------------------------------
  # Category-based access rights (access_to_category)
  # ---------------------------------------------------------------------------

  Scenario: Investor gains access via category-based access right
    Given there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    And the investor "Big LP" has category "LP"
    And I grant "read" access to the fund for category "LP"
    And there is an approved investor access for "lp@example.com" and investor "Big LP"
    Then the user "lp@example.com" should be allowed "show" on the fund

  Scenario: Investor in a different category does not get category-based access
    Given there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    And the investor "Big LP" has category "Co-Investor"
    And I grant "read" access to the fund for category "LP"
    And there is an approved investor access for "lp@example.com" and investor "Big LP"
    Then the user "lp@example.com" should be denied "show" on the fund

  Scenario: Category access right covers all investors in that category
    Given there is an entity "name=Investor Firm 2;entity_type=Investor"
    And there is an investor "investor_name=Small LP" for the entity "name=Fund Entity" with investor_entity "name=Investor Firm 2"
    And there is a user "email=lp1@example.com" for the entity "name=Investor Firm"
    And the user "lp1@example.com" has role "investor"
    And there is a user "email=lp2@example.com" for the entity "name=Investor Firm 2"
    And the user "lp2@example.com" has role "investor"
    And the investor "Big LP" has category "LP"
    And the investor "Small LP" has category "LP"
    And I grant "read" access to the fund for category "LP"
    And there is an approved investor access for "lp1@example.com" and investor "Big LP"
    And there is an approved investor access for "lp2@example.com" and investor "Small LP"
    Then the user "lp1@example.com" should be allowed "show" on the fund
    And the user "lp2@example.com" should be allowed "show" on the fund

  # ---------------------------------------------------------------------------
  # Investor Scope (for_investor)
  # ---------------------------------------------------------------------------

  Scenario: Investor scope includes fund when both gates pass
    Given there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    And I grant "read" access to the fund for investor "Big LP"
    And there is an approved investor access for "lp@example.com" and investor "Big LP"
    Then the fund scope for user "lp@example.com" should include "Main Fund"

  Scenario: Investor scope excludes fund when InvestorAccess is unapproved
    Given there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    And I grant "read" access to the fund for investor "Big LP"
    And there is an unapproved investor access for "lp@example.com" and investor "Big LP"
    Then the fund scope for user "lp@example.com" should not include "Main Fund"

  Scenario: Investor scope excludes fund when there is no access right
    Given there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    And there is an approved investor access for "lp@example.com" and investor "Big LP"
    Then the fund scope for user "lp@example.com" should not include "Main Fund"

  # ---------------------------------------------------------------------------
  # Cross-entity isolation
  # ---------------------------------------------------------------------------

  Scenario: User from a different entity cannot access the fund
    Given there is an entity "name=Other Entity;entity_type=Investment Fund"
    And there is a user "email=outsider@example.com" for the entity "name=Other Entity"
    And the user "outsider@example.com" has role "employee"
    Then the user "outsider@example.com" should be denied "show,update,destroy" on the fund

  Scenario: Investor from a different fund entity cannot access another fund entity's fund
    Given there is an entity "name=Other Fund Entity;entity_type=Investment Fund"
    And there is a fund "name=Other Fund" for the entity "name=Other Fund Entity"
    And there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    And there is an approved investor access for "lp@example.com" and investor "Big LP"
    # Use named-fund step because creating Other Fund above overwrites @fund
    And I grant "read" access to "Main Fund" for investor "Big LP"
    Then the user "lp@example.com" should be denied "show" on "Other Fund"

  # ---------------------------------------------------------------------------
  # Metadata restrictions
  # ---------------------------------------------------------------------------

  Scenario: Investor access right with ReadOnly metadata blocks update
    Given there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    And I grant "read" access to the fund for investor "Big LP" with metadata "ReadOnly"
    And there is an approved investor access for "lp@example.com" and investor "Big LP"
    Then the user "lp@example.com" should pass metadata check "ReadOnly" on the fund
    And the user "lp@example.com" should fail metadata check "FullAccess" on the fund

  # ---------------------------------------------------------------------------
  # Investor Advisor - success and failure
  #
  # An advisor must:
  #   1. Have an InvestorAdvisor record linking them to the advising entity
  #   2. Switch into that entity (entity_id changes to the advising entity)
  #   3. Have an AccessRight with user_id=advisor.id scoped to the advising entity
  #   4. Have an approved InvestorAccess for the specific investor
  #
  # Two fixture invariants are easy to get wrong here, and both fail in a way that looks like
  # an access-rights bug rather than a setup mistake:
  #
  #   a) The advisor's OWN firm must be entity_type=Investor Advisor (Advisor Firm below, not
  #      Investor Firm). Only that branch of User#setup_defaults records advisor_entity_id, and
  #      User#investor_advisor? reads that column, NOT the investor_advisor role. Put the advisor
  #      in an Investor entity and investor_advisor? stays false even after switching, so the
  #      policies quietly take the plain-investor branch and these scenarios pass while testing
  #      something else entirely.
  #
  #   b) The InvestorAdvisor grant must carry permissions. Once switched in, User#get_permissions
  #      reads the GRANT's permissions instead of the user's own, so a grant with none leaves
  #      every enable_* flag false and FundPolicy#show? denies on its first condition, before any
  #      access right is looked at. The switch step sets these; see access_rights_cache_steps.rb.
  # ---------------------------------------------------------------------------

  Scenario: Advisor switched into entity with AR and approved InvestorAccess can access fund
    Given there is a user "email=advisor@example.com" for the entity "name=Advisor Firm"
    And the user "advisor@example.com" has role "investor_advisor"
    And the advisor "advisor@example.com" is switched into entity "name=Fund Entity"
    And I grant "read" access to the fund for user "advisor@example.com"
    And there is an approved investor access for "advisor@example.com" and investor "Big LP"
    Then the user "advisor@example.com" should be allowed "show" on the fund

  Scenario: Advisor switched into entity but no AR cannot access fund
    Given there is a user "email=advisor@example.com" for the entity "name=Advisor Firm"
    And the user "advisor@example.com" has role "investor_advisor"
    And the advisor "advisor@example.com" is switched into entity "name=Fund Entity"
    And there is an approved investor access for "advisor@example.com" and investor "Big LP"
    Then the user "advisor@example.com" should be denied "show" on the fund

  Scenario: Advisor switched into entity cannot access a fund they have no access right for
    # permissioned_investor_advisor? is a single gate: requires only a user_id AR, NOT InvestorAccess.
    # Denial is caused by the missing AR, not by InvestorAccess absence.
    Given there is a user "email=advisor@example.com" for the entity "name=Advisor Firm"
    And the user "advisor@example.com" has role "investor_advisor"
    And the advisor "advisor@example.com" is switched into entity "name=Fund Entity"
    # No AR exists for this advisor on Main Fund
    Then the user "advisor@example.com" should be denied "show" on the fund

  Scenario: Advisor with AR on one fund is denied on another fund in the same entity without AR
    # AR is scoped to a specific fund; switching into an entity grants NO blanket access to all its funds.
    Given there is a user "email=advisor@example.com" for the entity "name=Advisor Firm"
    And the user "advisor@example.com" has role "investor_advisor"
    And the advisor "advisor@example.com" is switched into entity "name=Fund Entity"
    # Create Second Fund — @fund now points to Second Fund; advisor has no AR for it
    And there is a fund "name=Second Fund" for the entity "name=Fund Entity"
    Then the user "advisor@example.com" should be denied "show" on the fund

  Scenario: Advisor with full CRUD AR can show and mutate fund
    Given there is a user "email=advisor@example.com" for the entity "name=Advisor Firm"
    And the user "advisor@example.com" has role "investor_advisor"
    And the advisor "advisor@example.com" is switched into entity "name=Fund Entity"
    And I grant "create,read,update,destroy" access to the fund for user "advisor@example.com"
    And there is an approved investor access for "advisor@example.com" and investor "Big LP"
    Then the user "advisor@example.com" should be allowed "show,update,destroy" on the fund

  Scenario: Advisor with read-only AR cannot mutate fund
    Given there is a user "email=advisor@example.com" for the entity "name=Advisor Firm"
    And the user "advisor@example.com" has role "investor_advisor"
    And the advisor "advisor@example.com" is switched into entity "name=Fund Entity"
    And I grant "read" access to the fund for user "advisor@example.com"
    And there is an approved investor access for "advisor@example.com" and investor "Big LP"
    Then the user "advisor@example.com" should be allowed "show" on the fund
    And the user "advisor@example.com" should be denied "update,destroy" on the fund

  Scenario: Advisor not switched (home entity) cannot access advised entity's fund
    Given there is a user "email=advisor@example.com" for the entity "name=Advisor Firm"
    And the user "advisor@example.com" has role "investor_advisor"
    And there is an investor advisor record for "advisor@example.com" on entity "name=Fund Entity"
    And I grant "read" access to the fund for user "advisor@example.com"
    And there is an approved investor access for "advisor@example.com" and investor "Big LP"
    # User has NOT switched — their entity_id is still Investor Firm
    Then the user "advisor@example.com" should be denied "show" on the fund

  Scenario: Advisor scope includes fund after switch
    Given there is a user "email=advisor@example.com" for the entity "name=Advisor Firm"
    And the user "advisor@example.com" has role "investor_advisor"
    And the advisor "advisor@example.com" is switched into entity "name=Fund Entity"
    And I grant "read" access to the fund for user "advisor@example.com"
    And there is an approved investor access for "advisor@example.com" and investor "Big LP"
    Then the fund scope for user "advisor@example.com" should include "Main Fund"

  Scenario: Advisor scope excludes fund when not switched
    Given there is a user "email=advisor@example.com" for the entity "name=Advisor Firm"
    And the user "advisor@example.com" has role "investor_advisor"
    And there is an investor advisor record for "advisor@example.com" on entity "name=Fund Entity"
    And I grant "read" access to the fund for user "advisor@example.com"
    And there is an approved investor access for "advisor@example.com" and investor "Big LP"
    Then the fund scope for user "advisor@example.com" should not include "Main Fund"

  # ---------------------------------------------------------------------------
  # Denied access: employee trying to access as investor and vice versa
  # ---------------------------------------------------------------------------

  Scenario: Employee with AR cannot access another entity's fund as if they were an investor
    Given there is an entity "name=Other Fund Entity;entity_type=Investment Fund"
    And there is a fund "name=Other Fund" for the entity "name=Other Fund Entity"
    And there is a user "email=emp@example.com" for the entity "name=Fund Entity"
    And the user "emp@example.com" has role "employee"
    When I grant "read" access to the fund for user "emp@example.com"
    Then the user "emp@example.com" should be denied "show" on "Other Fund"

  Scenario: Investor with AR on their fund cannot access an unrelated fund
    Given there is an entity "name=Other Fund Entity;entity_type=Investment Fund"
    And there is a fund "name=Other Fund" for the entity "name=Other Fund Entity"
    And there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    # Use the named-fund step because creating Other Fund above overwrites @fund
    And I grant "read" access to "Main Fund" for investor "Big LP"
    And there is an approved investor access for "lp@example.com" and investor "Big LP"
    Then the user "lp@example.com" should be denied "show" on "Other Fund"

  # ---------------------------------------------------------------------------
  # Access right on capital commitment (child record inherits fund AR)
  # ---------------------------------------------------------------------------

  Scenario: Employee with fund access right can access capital commitments
    Given there is a user "email=emp@example.com" for the entity "name=Fund Entity"
    And the user "emp@example.com" has role "employee"
    And the fund has a capital commitment from investor "Big LP"
    When I grant "read" access to the fund for user "emp@example.com"
    Then the user "emp@example.com" should be allowed "show" on the capital commitment

  Scenario: Investor with fund access and approved InvestorAccess can access their commitment
    Given there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    And the fund has a capital commitment from investor "Big LP"
    And I grant "read" access to the fund for investor "Big LP"
    And there is an approved investor access for "lp@example.com" and investor "Big LP"
    Then the user "lp@example.com" should be allowed "show" on the capital commitment

  Scenario: Investor cannot access another investor's capital commitment
    Given there is an entity "name=Other Investor Firm;entity_type=Investor"
    And there is an investor "investor_name=Other LP" for the entity "name=Fund Entity" with investor_entity "name=Other Investor Firm"
    And there is a user "email=lp@example.com" for the entity "name=Investor Firm"
    And the user "lp@example.com" has role "investor"
    And the fund has a capital commitment from investor "Big LP"
    And the fund has a capital commitment from investor "Other LP"
    And I grant "read" access to the fund for investor "Big LP"
    And there is an approved investor access for "lp@example.com" and investor "Big LP"
    Then the user "lp@example.com" should be denied "show" on the capital commitment of "Other LP"
