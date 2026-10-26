@rack_test
Feature: The fund's money figures as of a date
  The fund's as-of view gives committed, call, collected, distribution and units premium as of a date, from the same
  rows the fund's own running totals are rolled up from.
  Worked examples: openspec/changes/portfolio-report-fund-metrics/design.md#worked-examples

Background:
  Given Im logged in as a user "first_name=Meera" for an entity "name=Alpha Ventures;entity_type=Investment Fund"
  Given the user has role "company_admin"

# H18 — Happy path: asked as of today, each figure equals the fund's own running total
Scenario: As of today matches the fund's own figures
  Given a fund with commitments, collections, distributions and units all dated in the past
  When the fund is viewed as of "today"
  Then each as-of figure equals the fund's own figure

# E27 — Edge case: a commitment dated after the date is not counted
Scenario: Commitment after the date is not counted
  Given a fund with commitments, collections, distributions and units, some dated after 30 September 2026
  When the fund is viewed as of "2026-09-30"
  Then the committed amount leaves out the commitment dated after that day

# E28 — Edge case: a verified payment received after the date is not counted
Scenario: Collection after the date is not counted
  Given a fund with commitments, collections, distributions and units, some dated after 30 September 2026
  When the fund is viewed as of "2026-09-30"
  Then the collected amount leaves out the payment received after that day

# E29 — Edge case: a payment on a remittance that is not verified is not counted
Scenario: Unverified collection is not counted
  Given a fund with commitments, collections, distributions and units, some dated after 30 September 2026
  When the fund is viewed as of "2026-09-30"
  Then the collected amount leaves out the payment on the unverified remittance

# E30 — Edge case: a distribution payment dated after the date is not counted
Scenario: Distribution after the date is not counted
  Given a fund with commitments, collections, distributions and units, some dated after 30 September 2026
  When the fund is viewed as of "2026-09-30"
  Then the distribution amount leaves out the distribution payment dated after that day

# E31 — Edge case: units premium counts only units issued up to the date
Scenario: Units premium counts units issued up to the date
  Given a fund with commitments, collections, distributions and units, some dated after 30 September 2026
  When the fund is viewed as of "2026-09-30"
  Then the total units premium leaves out the unit issued after that day
