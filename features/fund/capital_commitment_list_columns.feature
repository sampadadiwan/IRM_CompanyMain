@rack_test
Feature: Capital commitment list columns follow the page
  The entity's saved commitment columns apply to every commitments list, so the page
  adds the fund / stakeholder columns it needs (and drops the one it does not).

Background:
  Given there is a user "" for an entity "entity_type=Investment Fund"
  And the entity has saved commitment columns "folio_id,investor_name,unit_type,committed_amount"

Scenario: Investor page Commitments tab shows the fund, not the stakeholder
  When the commitment columns are resolved for the "investor tab"
  Then the commitment columns should be "fund_name,folio_id,unit_type,committed_amount"

Scenario: Cross-fund commitments index shows both fund and stakeholder
  When the commitment columns are resolved for the "cross-fund index"
  Then the commitment columns should be "fund_name,folio_id,investor_name,unit_type,committed_amount"

Scenario: A single fund's commitments keep the saved columns
  When the commitment columns are resolved for the "fund page"
  Then the commitment columns should be "folio_id,investor_name,unit_type,committed_amount"
