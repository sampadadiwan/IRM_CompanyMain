# Security review 2026-10, C3 — AI Portfolio Reports: tenant isolation, stored XSS and the pandoc call.
# A report belongs to a firm only through its portfolio company (Option A: no entity_id column), so
# Artha's users must not reach Zeta's reports, companies, folders or templates. Section and collated
# HTML is sanitized by AiReportHtml when stored, when shown and when returned as JSON.
# Worked examples: docs/security/security_review_2026_10.md (## C3 — AI Portfolio Reports)
@security @rack_test
Feature: AI Portfolio Reports stay inside the firm that owns the portfolio company

  Background:
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And a portfolio company "Artha Robotics" exists
    And another firm "Zeta Capital" has a portfolio company "Zeta Labs" with an AI portfolio report

  # C3-1 — Error case: Artha's user cannot open Zeta's report, its edit page, collated view or exports
  Scenario: C3-1 Zeta's report cannot be viewed by Artha
    When I open Zeta's AI portfolio report pages
    Then each of them is refused

  # C3-2 — Error case: the reports list shows Artha's report and not Zeta's
  Scenario: C3-2 Zeta's report is not listed for Artha
    Given an AI portfolio report exists for "Artha Robotics"
    When I visit the AI portfolio reports list
    Then the list shows the report for "Artha Robotics"
    And the list does not show the report for "Zeta Labs"

  # C3-3 — Error case: saving or deleting Zeta's report is refused and the report is unchanged
  Scenario: C3-3 Artha cannot save or delete Zeta's report
    When I save Zeta's collated report as "<p>Overwritten by Artha</p>"
    Then I am refused
    When I delete Zeta's AI portfolio report
    Then I am refused
    And Zeta's report is unchanged

  # C3-4 — Error case: opening Zeta's evaluation documents is refused before any folder is created
  Scenario: C3-4 Artha cannot open Zeta's evaluation documents
    When I open the evaluation documents of "Zeta Labs"
    Then I am refused
    And nothing was created in "Zeta Capital"

  # C3-5 — Error case: uploading evaluation documents for Zeta is refused; no folder or document is created
  Scenario: C3-5 Artha cannot upload evaluation documents for Zeta
    When I upload an evaluation document "deck.pdf" for "Zeta Labs"
    Then I am refused
    And nothing was created in "Zeta Capital"

  # C3-6 — Error case: updating or appending to a section of Zeta's report is refused
  Scenario: C3-6 Artha cannot update a section of Zeta's report
    When I save the "Company Overview" section of Zeta's report as "<p>Overwritten by Artha</p>"
    Then I am refused
    When I add "<p>Appended by Artha</p>" to the "Company Overview" section of Zeta's report
    Then I am refused
    And Zeta's report is unchanged

  # C3-7 — Edge case: img onerror and script are stripped when a section is saved, returned and shown; the text stays
  Scenario: C3-7 Script and image HTML is stripped from section content
    Given an AI portfolio report exists for "Artha Robotics"
    When I save the "Company Overview" section of my report as:
      """
      <p>Revenue grew 40%</p><img src="x" onerror="alert(1)"><script>alert(2)</script>
      """
    Then the "Company Overview" section of my report is stored without img or script and keeps "Revenue grew 40%"
    When I add "<p>Board approved</p><img src=x onerror=alert(5)>" to the "Company Overview" section of my report
    Then the returned content has no img or script and keeps "Board approved"
    Given the "Key Risks" section of my report was stored before sanitizing as:
      """
      <p>Customer concentration</p><img src="x" onerror="alert(3)"><script>alert(4)</script>
      """
    When I open the "Key Risks" section of my report
    Then the section editor shows "Customer concentration" without img, script or event handlers

  # C3-8 — Edge case: collated HTML with a local-file img; the DOCX export hands pandoc no img and still succeeds
  Scenario: C3-8 The DOCX export gives pandoc sanitized HTML through an argument list
    Given an AI portfolio report exists for "Artha Robotics"
    And my report's collated HTML was stored before sanitizing with a local-file image
    And pandoc is recorded
    When I export my report as DOCX
    Then the export succeeds as a Word document
    And pandoc was called with an argument list and its input has no img

  # C3-9 — Error case: a report cannot be created with another firm's investment criteria template
  Scenario: C3-9 Artha cannot create a report with Zeta's investment criteria template
    Given "Zeta Capital" has an investment criteria template "Zeta Thesis"
    When I create an AI portfolio report for "Artha Robotics" using the template "Zeta Thesis"
    Then I am refused
    And no AI portfolio report was created for "Artha Robotics"
    And no evaluation folder was created for "Artha Robotics"

  # C3-H — Happy path: Artha's own report is created, viewed, edited and exported; chart, web link, table and style survive
  Scenario: C3-H Artha's own report works end to end
    Given the portfolio company "Artha Robotics" has an evaluation folder with documents:
      | name           |
      | pitch_deck.pdf |
    And report generation is stubbed
    When I create an AI portfolio report for "Artha Robotics"
    Then an AI portfolio report is created for "Artha Robotics" reading its evaluation folder
    When I open the "Company Overview" section of my report
    Then the request succeeds
    When I save the "Company Overview" section of my report with a chart, a web link, a table and inline style
    Then the request succeeds
    And the "Company Overview" section of my report keeps the chart, the web link, the table and the inline style
    When I open the "Company Overview" section of my report
    Then the section editor shows the chart and the web link
    Given PDF rendering is recorded
    When I export my report as PDF
    Then the PDF export succeeds and keeps the web link and the chart box
    Given pandoc is recorded
    When I export my report as DOCX
    Then the export succeeds as a Word document
    And pandoc's input keeps the web link

  # C3-X — Error case: the new-report form offers only Artha's portfolio companies
  Scenario: C3-X The new-report form lists only Artha's portfolio companies
    Given I am at the new AI portfolio report page
    Then the portfolio company list offers "Artha Robotics"
    And the portfolio company list does not offer "Zeta Labs"
