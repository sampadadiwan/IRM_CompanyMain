@rack_test
Feature: Portfolio report holdings at a date
  Investments are valued as of a date by one helper, and the report works out the days it needs from text dates.
  Worked examples: openspec/changes/portfolio-report-fund-metrics/design.md#worked-examples

Background:
  Given Im logged in as a user "first_name=Meera" for an entity "name=Alpha Ventures;entity_type=Investment Fund"
  Given the user has role "company_admin"
  And the Inflexor quarter data

# X1 — Error case: three dates in one run are each valued from a fresh load, with no frozen record reused
Scenario: The same investments are valued for three dates in a row
  When the investments of "Company A" in the fund are valued as of "2026-09-30", then "2026-06-30", then "2026-03-31"
  Then the values are "60.0", "50.0" and "45.0" crore

# X2 — Error case: the job passes the dates as text; the day before the start is worked out from them
Scenario: Dates arrive as text
  Given the consolidated generator is given the dates "2026-07-01" and "2026-09-30" as text
  Then the day before its start date is "2026-06-30"

# X3 — Error case: records that are already loaded are refused, so nothing is valued twice
Scenario: Already loaded investments are refused
  When already loaded investments are handed to the holdings helper
  Then the helper refuses them with an error that says they are already loaded
