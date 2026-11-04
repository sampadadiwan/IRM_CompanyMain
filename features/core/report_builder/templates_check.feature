@rack_test @report_builder
Feature: Report Builder starter templates — the template check

  Worked examples: openspec/changes/report-builder-starting-points/business-rules.md
  Every starter template in config/report_builder_templates.yml is checked
  against the column catalog and run, so a data change can't make a template
  come out blank. A failure names the template and the problem.

  Background:
    Given the Acme report builder data

  # H12 — Happy path: every shipped template validates, creates a report and runs on Acme
  Scenario: Templates are checked
    Then every starter template passes the template check

  # X1 — Error case: a template using a column that doesn't exist fails, naming the template and the column
  Scenario: Check names template and column
    Given the template "lp_capital_account" uses the column "capital_commitments.no_such" instead of "capital_commitments.call_amount"
    When I run the template check on "lp_capital_account"
    Then the template check fails with "LP Capital Account Summary: capital_commitments.no_such isn't a column of capital commitments"
