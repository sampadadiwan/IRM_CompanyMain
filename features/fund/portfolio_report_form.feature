@javascript
Feature: Portfolio report form
  The sections of a report are not used by a consolidated report.
  Worked examples: openspec/changes/portfolio-report-combined-packet/design.md#worked-examples

Background:
  Given Im logged in as a user "first_name=Meera" for an entity "name=Alpha Ventures;entity_type=Investment Fund"
  Given the user has role "company_admin"

# H16 — ticking Consolidated hides the sections, unticking shows them again
Scenario: Sections are hidden while Consolidated is ticked
  When I open the new portfolio report form
  Then the sections and the Add Section button are shown
  When I tick Consolidated
  Then the sections and the Add Section button are hidden
  When I untick Consolidated
  Then the sections and the Add Section button are shown
