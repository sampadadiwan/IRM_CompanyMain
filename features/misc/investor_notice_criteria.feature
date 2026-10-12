Feature: Investor notices can be further narrowed by a criteria expression
  As a GP publishing an investor notice
  I want to optionally restrict a notice, on top of its existing audience, to
  only investors matching a criteria expression
  So that I can target a notice more precisely without creating a separate
  notice for every sub-group, and without risking arbitrary code execution
  from a GP-authored expression

  # InvestorNoticeCriteriaEvaluator never uses Ruby eval — it parses the
  # expression with Dentaku (a safe formula evaluator, already used elsewhere
  # in this codebase for report-builder formulas) against an explicit
  # allow-list of variables. It's checked at render time, per viewer, on top
  # of the existing InvestorNoticeEntry audience — it can only narrow that
  # audience further, never expand it.

  Background:
    Given there is an entity "name=Criteria GP;entity_type=Investment Fund;enable_funds=true"
    Given there is an investor "Category Match LP" with an approved login
    Given there is an investor "Category Mismatch LP" with an approved login

  @rack_test
  Scenario: A notice with no criteria still reaches everyone in its audience
    Given there is an entity-wide investor notice titled "General Notice" with generate enabled
    When the investor notice job runs for "General Notice"
    And I login as investor "Category Match LP"
    And I visit the investor dashboard
    Then I should see the investor notice "General Notice"

  @rack_test
  Scenario: A criteria expression narrows an entity-wide notice to matching investors only
    Given there is an entity-wide investor notice titled "Lead Investor Notice" with generate enabled
    And the investor "Category Match LP" has category "Lead Investor"
    And the investor "Category Mismatch LP" has category "Co-Investor"
    And the investor notice "Lead Investor Notice" has criteria "[investor.category] == \"Lead Investor\""
    When the investor notice job runs for "Lead Investor Notice"
    And I login as investor "Category Match LP"
    And I visit the investor dashboard
    Then I should see the investor notice "Lead Investor Notice"
    When I log out
    And I login as investor "Category Mismatch LP"
    And I visit the investor dashboard
    Then I should not see the investor notice "Lead Investor Notice"

  Scenario: An unresolvable criteria hides the notice rather than crashing the dashboard
    Given there is an entity-wide investor notice titled "Broken Criteria Notice" with generate enabled
    And the investor notice "Broken Criteria Notice" has criteria "[nonexistent.field] == \"x\"" without validation
    When the investor notice job runs for "Broken Criteria Notice"
    And I login as investor "Category Match LP"
    And I visit the investor dashboard
    Then I should not see the investor notice "Broken Criteria Notice"

  @rack_test
  Scenario: A malformed criteria expression is rejected when saving the notice
    Given there is an entity-wide investor notice titled "Draft Notice" with generate enabled
    Then setting the investor notice "Draft Notice" criteria to "[investor.category] ===" should be rejected

  # criteria is powerful/technical enough (a raw expression) to reserve for
  # CapHive support, same gate as the other Dentaku formula fields in this
  # app (FundFormula#formula, CallFee#formula) — a GP company_admin shouldn't
  # see or set it.
  @rack_test
  Scenario: Only support can edit the criteria field
    Given there is a user "email=admin@supportgategp.example.com" for the entity "name=Criteria GP"
    Given the user "admin@supportgategp.example.com" has role "company_admin"
    Given there is a user "email=support@caphive.example.com" for the entity "name=Criteria GP"
    Given the user "support@caphive.example.com" has role "support"
    Given there is an entity-wide investor notice titled "Gated Notice" with generate enabled
    When I log in with email "admin@supportgategp.example.com"
    And I visit the edit page for the investor notice "Gated Notice"
    Then the criteria field should not be present
    When I log out
    And I log in with email "support@caphive.example.com"
    And I visit the edit page for the investor notice "Gated Notice"
    Then the criteria field should be present

  # A concrete real-world criteria use case: a "please add your phone number"
  # nudge that should only bother investors who haven't done so — exercises
  # the [user.phone] variable (the login user's own attribute, not the
  # Investor/firm row) and confirms it reflects live per-viewer state, not
  # something baked in at generation time.
  Scenario: "Add your phone number" notice only shows for investors missing a phone number
    Given there is an entity-wide investor notice titled "Add your phone number" with generate enabled
    And the investor notice "Add your phone number" has a line item titled "Update your profile" linking to the edit profile page
    And the investor notice "Add your phone number" has criteria "[user.phone] == \"\""
    When the investor notice job runs for "Add your phone number"
    And investor "Category Match LP" has no phone number
    # A dialable number for the default +91 call code: the criteria only tests presence,
    # but the write now goes through User#phone_must_be_dialable.
    And investor "Category Mismatch LP" has phone number "9000000100"
    And I login as investor "Category Match LP"
    And I visit the investor dashboard
    Then I should see the investor notice "Add your phone number"
    When I log out
    And I login as investor "Category Mismatch LP"
    And I visit the investor dashboard
    Then I should not see the investor notice "Add your phone number"
