Feature: Value Bridge Calculation
  As a user
  I want to see the value bridge calculation
  So that I can understand the drivers of enterprise value change between two dates.

  Scenario Outline: Check Value bridge creation
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the entity has custom fields "<custom_fields>" for "Valuation"
    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    Given there is an investment instrument for the portfolio company "name=Equity;category=Unlisted;sub_category=Equity;sector=Tech"
    Given there is a valuation "per_share_value_cents=12000;valuation_date=01/01/2025" for the portfolio company
    And the valuation custom fields are filled out with "<custom_field_values1>"
    Given there is a valuation "per_share_value_cents=20000;valuation_date=01/04/2024" for the portfolio company
    And the valuation custom fields are filled out with "<custom_field_values2>"
    When the value bridge is created between the two valuations
    Then I should see the value bridge details on the details page
    Examples:
    |custom_fields| custom_field_values1| custom_field_values2|
    |name=net_debt;field_type=NumberField#name=revenue;field_type=NumberField#name=ebitda_margin;field_type=NumberField#name=ebitda;field_type=Calculation;meta_data=json_fields['revenue'].to_f * json_fields['ebitda_margin'].to_f / 100#name=valuation_multiple;field_type=NumberField#name=enterprise_value;field_type=Calculation;meta_data=json_fields['ebitda'].to_f * json_fields['valuation_multiple'].to_f|net_debt=500;revenue=1500;ebitda_margin=12;valuation_multiple=12 | net_debt=300;revenue=650;ebitda_margin=15.4;valuation_multiple=10 |
