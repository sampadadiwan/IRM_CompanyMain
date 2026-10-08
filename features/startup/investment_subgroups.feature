Feature: Investment subgroups and per-instrument cap table rows
  As a portfolio company cap table user
  I want to tag investments with a subgroup and see each instrument on its own row
  So that the cap table groups investors the same way whether the data came from investments or shareholder positions

  Spec: openspec/changes/investment-subgroups-and-captable-actions/specs/startups/investment-subgroups/spec.md

  Background:
    Given Im logged in as a user "" for an entity "name=Startup Inc;entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "investor_name=Startup Inc;category=Portfolio Company"

  Scenario: A subgroup entered on the investment form is saved and shown on the investment page
    Given the entity has an exchange rate from "USD" to "INR"
    When I create an investment for "Startup Inc" through the form with:
      | currency            | USD               |
      | category            | Other             |
      | investor_name       | NorthInc Ventures |
      | investment_type     | Convertible       |
      | subgroup            | Institutional     |
      | funding_round       | Series A          |
      | quantity            | 1500              |
      | instrument_name     | CCPS Series A     |
      | instrument_quantity | 15                |
      | price               | 100               |
      | investment_date     | 2025-06-25        |
    Then I should see "Investment was successfully created."
    And the investment for "NorthInc Ventures" should have:
      | subgroup            | Institutional |
      | instrument_name     | CCPS Series A |
      | instrument_quantity | 15            |
    When I visit the investment for "NorthInc Ventures"
    Then I should see "Subgroup"
    And I should see "Institutional"

  Scenario: The form labels the type as Instrument Type and only asks for instrument details for a Convertible
    When I open the new investment form for "Startup Inc"
    Then I should see "Instrument Type"
    And I should see "Subgroup"
    When I choose instrument type "Equity"
    Then I should not see the instrument name and quantity fields
    When I choose instrument type "Convertible"
    Then I should see the instrument name and quantity fields

  Scenario: A subgroup longer than 100 characters is rejected
    Given the entity has an exchange rate from "USD" to "INR"
    When I create an investment for "Startup Inc" through the form with:
      | currency        | USD                                                                                                   |
      | category        | Other                                                                                                 |
      | investor_name   | Long Subgroup Fund                                                                                    |
      | investment_type | Equity                                                                                                |
      | subgroup        | AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA |
      | funding_round   | Seed                                                                                                  |
      | quantity        | 100                                                                                                   |
      | price           | 1                                                                                                     |
      | investment_date | 2025-01-01                                                                                            |
    Then I should see "too long"
    And no investment should exist for "Long Subgroup Fund"

  Scenario: An Equity investment never keeps an instrument name or instrument quantity
    Given there are the following investments for "Startup Inc":
      | investor_name | category | investment_type | funding_round | quantity | price | investment_date | instrument_name | instrument_quantity |
      | John Doe      | Founder  | Equity          | Seed          | 1000     | 1.0   | 2024-01-01      | CCPS            | 10                  |
    Then the investment for "John Doe" should have:
      | instrument_name     |  |
      | instrument_quantity |  |

  Scenario: Investments can be filtered by subgroup
    Given there are the following investments for "Startup Inc":
      | investor_name     | category | investment_type | funding_round | quantity | price | investment_date | subgroup      |
      | John Doe          | Founder  | Equity          | Seed          | 1000     | 1.0   | 2024-01-01      |               |
      | NorthInc Ventures | Other    | Equity          | Seed          | 500      | 1.0   | 2024-01-01      | Institutional |
    When I filter the "investments" by "subgroup=Institutional"
    Then I should see "NorthInc Ventures"
    And I should not see "John Doe"

  Scenario: The horizontal cap table nests investors with a subgroup under that subgroup
    Given there are the following investments for "Startup Inc":
      | investor_name     | category | investment_type | funding_round | quantity | price | investment_date | subgroup      | instrument_name | instrument_quantity |
      | John Doe          | Founder  | Equity          | Seed          | 1000     | 1.0   | 2024-01-01      |               |                 |                     |
      | Angel One         | Other    | Equity          | Seed          | 100      | 1.0   | 2024-01-01      | Angel         |                 |                     |
      | NorthInc Ventures | Other    | Convertible     | Series A      | 500      | 1.0   | 2025-06-25      | Institutional | CCPS Series A   | 5                   |
    When I go to the captable of the portfolio company
    Then the horizontal cap table should have these investor rows:
      | category | subgroup      | investor          | instrument    |
      | Founders |               | John Doe          | Equity        |
      | Others   | Angel         | Angel One         | Equity        |
      | Others   | Institutional | NorthInc Ventures | CCPS Series A |

  Scenario: An investor tagged with a subgroup in only one round still gets a single row under that subgroup
    Given there are the following investments for "Startup Inc":
      | investor_name     | category | investment_type | funding_round | quantity | price | investment_date | subgroup      |
      | NorthInc Ventures | Other    | Equity          | Seed          | 100      | 1.0   | 2024-01-01      |               |
      | NorthInc Ventures | Other    | Equity          | Series A      | 50       | 1.0   | 2025-06-25      | Institutional |
    When I go to the captable of the portfolio company
    Then the horizontal cap table should have these investor rows:
      | category | subgroup      | investor          | instrument |
      | Others   | Institutional | NorthInc Ventures | Equity     |

  Scenario: An investor holding Equity and a Convertible gets a separate row per instrument
    Given there are the following investments for "Startup Inc":
      | investor_name | category | investment_type | funding_round | quantity | price | investment_date | instrument_name | instrument_quantity |
      | John Doe      | Founder  | Equity          | Seed          | 1000     | 1.0   | 2024-01-01      |                 |                     |
      | John Doe      | Founder  | Convertible     | Seed          | 1000     | 1.0   | 2024-01-01      | CCPS            | 10                  |
    When I go to the captable of the portfolio company
    Then the horizontal cap table should have these investor rows:
      | category | subgroup | investor | instrument |
      | Founders |          | John Doe | Equity     |
      | Founders |          | John Doe | CCPS       |
    And the "Seed" round cap table should have these rows:
      | investor | instrument | quantity | percentage | fully diluted | fully diluted % |
      | John Doe | Equity     | 1000     | 99.01%     | 1000          | 50.0%           |
      | John Doe | CCPS       | 10       | 0.99%      | 1000          | 50.0%           |
      | Total    | -          | 1010     | 100.0%     | 2000          | 100.0%          |

  Scenario: An investor with investments under two categories keeps one row per category
    Given there are the following investments for "Startup Inc":
      | investor_name | category | investment_type | funding_round | quantity | price | investment_date | instrument_name | instrument_quantity |
      | John Doe      | Founder  | Equity          | Seed          | 1000     | 1.0   | 2024-01-01      |                 |                     |
      | John Doe      | Other    | Convertible     | Seed          | 500      | 1.0   | 2024-01-01      | CCPS            | 5                   |
    When I go to the captable of the portfolio company
    Then the horizontal cap table should have these investor rows:
      | category | subgroup | investor | instrument |
      | Founders |          | John Doe | Equity     |
      | Others   |          | John Doe | CCPS       |

  Scenario: Merging several investors into the horizontal cap table's Self row does not compound rounding error
    # Self holds 3 of 7 equal shares (3/7 = 42.857142...%, which rounds to 42.86%). Three separate
    # Investment records merge into the single Self row - if the merge re-parses the previous
    # merge's already-rounded display string instead of keeping an unrounded running total, the
    # error compounds across the three merges into "42.87%" instead of the correct "42.86%".
    Given there are the following investments for "Startup Inc":
      | investor_name | category | investment_type | funding_round | quantity | price | investment_date |
      | Founder A      | Self     | Equity           | Seed           | 1000     | 1.0   | 2024-01-01       |
      | Founder B      | Self     | Equity           | Seed           | 1000     | 1.0   | 2024-01-01       |
      | Founder C      | Self     | Equity           | Seed           | 1000     | 1.0   | 2024-01-01       |
      | Angel Fund     | Other    | Equity           | Seed           | 4000     | 1.0   | 2024-01-01       |
    When I go to the captable of the portfolio company
    Then the horizontal cap table should show "42.86%" as the "Seed" percentage for "Self"

  Scenario: A Convertible counts its instrument quantity as held and the rest of its quantity as dilution
    Given there are the following investments for "Startup Inc":
      | investor_name     | category | investment_type | funding_round | quantity | price | investment_date | instrument_name | instrument_quantity |
      | John Doe          | Founder  | Equity          | Seed          | 985      | 1.0   | 2024-01-01      |                 |                     |
      | NorthInc Ventures | Other    | Convertible     | Seed          | 1500     | 1.0   | 2024-01-01      | CCPS Series A   | 15                  |
    When I go to the captable of the portfolio company
    Then the "Seed" round cap table should have these rows:
      | investor          | instrument    | quantity | percentage | fully diluted | fully diluted % |
      | John Doe          | Equity        | 985      | 98.5%      | 985           | 39.64%          |
      | NorthInc Ventures | CCPS Series A | 15       | 1.5%       | 1500          | 60.36%          |
      | Total             | -             | 1000     | 100.0%     | 2485          | 100.0%          |
