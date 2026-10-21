Feature: Date range sanity rule for Investor Statements
  The start and end dates submitted to generate an Investor Statement on a capital commitment
  must fall within past_years before and future_years after today (default 20 / 20, blocker).
  A rejected request enqueues neither the commitment statement job nor the investing entity one.

  Background:
    Given there is a user "first_name=Test" for an entity "name=RuleTestFirm;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And the default validation rules are seeded
    And there is a fund "name=RuleTestFund;currency=INR" for the entity
    And there is a capital commitment for an investor with no notification subscribers
    And The commitments have investor kycs linked
    And I am at the login page
    And I fill and submit the login page
    And background jobs are captured instead of run

  Scenario: H3: An Investor Statement for in-range dates starts generation
    When I request an Investor Statement from "<1 year ago>" to "<today>"
    Then I see "Documentation generation started, please check back in a few mins."
    And a "CapitalCommitmentSoaJob" job is enqueued

  Scenario: X11: An Investor Statement with an end date 25 years from now is not generated
    When I request an Investor Statement from "<1 year ago>" to "<25 years from now>"
    Then I see the date "Investor Statement dates <1 year ago> – <25 years from now> must be within 20 years before and 20 years after today."
    And no "CapitalCommitmentSoaJob" job is enqueued
    And no "KycDocGenJob" job is enqueued

  Scenario: X11: An Investing Entity statement with an end date 25 years from now is not generated
    When I request an Investor Statement for Investing Entity from "<1 year ago>" to "<25 years from now>"
    Then I see the date "Investor Statement dates <1 year ago> – <25 years from now> must be within 20 years before and 20 years after today."
    And no "KycDocGenJob" job is enqueued
    And no "CapitalCommitmentSoaJob" job is enqueued
