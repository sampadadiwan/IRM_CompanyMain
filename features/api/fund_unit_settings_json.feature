Feature: Fund unit settings JSON — read back each class's fees (G45)
  A FundUnitSetting import writes one row per unit class (management fee, set-up fee, carry, GP units, ISIN).
  API callers read them back with GET /fund_unit_settings.json, filtered by fund or by the upload that wrote them.
  It used to answer 406: the JSON view existed but the index action had no JSON branch.

  Background:
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is a fund "name=Acme Growth Fund I;currency=INR;unit_types=A1,B1" for the entity
    And the fund has the unit settings:
      | name | management_fee | setup_fee | carry | gp_units |
      | A1   | 2.0            | 2.0       | 20    | false    |
      | B1   | 1.2            | 0.6       | 0     | true     |
    And I have an API token

  # H1 — Happy path: the fund's classes come back with every fee column the import writes (Demo Fund 2: 10 classes)
  Scenario: H1 Listing a fund's unit settings
    When "me" sends GET "/fund_unit_settings.json?fund_id={fund}&all=true"
    Then the API status is 200
    And the API answer is a list of 2 rows
    And the API answer at "0.name" is "A1"
    And the API answer at "0.management_fee" is "2.0"
    And the API answer at "0.setup_fee" is "2.0"
    And the API answer at "0.carry" is "20.0"
    And the API answer at "1.name" is "B1"
    And the API answer at "1.gp_units" is "true"

  # E1 — Edge case: another fund's classes are not in the list (fund_id is applied, not ignored)
  Scenario: E1 Another fund's unit settings are left out
    Given there is a second fund "name=Acme Growth Fund II;currency=INR;unit_types=Z1" for the entity
    And the second fund has a unit setting "Z1"
    When "me" sends GET "/fund_unit_settings.json?fund_id={fund}&all=true"
    Then the API answer is a list of 2 rows
    When "me" sends GET "/fund_unit_settings.json?fund_id={fund_b}&all=true"
    Then the API answer is a list of 1 row
    And the API answer at "0.name" is "Z1"

  # E2 — Edge case: import_upload_id returns only the rows that upload wrote, and names the upload on each row
  Scenario: E2 Reading back one upload's unit settings
    Given the unit setting "B1" was written by an import upload
    When "me" sends GET "/fund_unit_settings.json?import_upload_id={import_upload}&all=true"
    Then the API answer is a list of 1 row
    And the API answer at "0.name" is "B1"
    And the API answer at "0.import_upload_id" is "{import_upload}"
