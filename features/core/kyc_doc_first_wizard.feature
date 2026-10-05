Feature: Doc-First KYC Wizard
  As a fund admin I want to upload KYC documents and have fields pre-filled automatically
  As an investor I want to see the document upload form first when I open my KYC magic link,
  so the form is pre-filled and I have less to type

  Background:
    Given Im logged in as a user "" for an entity "name=DocWizardFund;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing investor "investor_name=DocWizardInvestor" with "1" users
    And the entity has kyc_doc_first_wizard enabled
    And there is a KycDocExtractorAgent with PAN and address extraction rules for the entity

  # ─────────────────────────────────────────────────────────────────────────────
  # 1. Doc-first upload form is shown (not the regular KYC form)
  # ─────────────────────────────────────────────────────────────────────────────

  @doc_wizard
  Scenario: Company admin sees the document upload form instead of the regular KYC form
    When I visit the new investor KYC page
    Then I should see "Upload KYC Documents"
    And I should see "Upload PAN / Tax ID"
    And I should see "Upload Address Proof"
    And I should see "Fill Form Manually"

  # ─────────────────────────────────────────────────────────────────────────────
  # 2. "Fill Form Manually" escape hatch skips the doc-first wizard
  # ─────────────────────────────────────────────────────────────────────────────

  @doc_wizard
  Scenario: Clicking "Fill Form Manually" bypasses the doc-first upload step
    When I visit the new investor KYC page
    And I click "Fill Form Manually"
    Then I should not see "Upload KYC Documents"

  # ─────────────────────────────────────────────────────────────────────────────
  # 3. Company admin: full wizard flow — upload docs → extraction → pre-filled form
  # ─────────────────────────────────────────────────────────────────────────────

  @doc_wizard
  Scenario: Company admin uploads documents and sees a pre-filled KYC edit form
    Given the LLM will extract "ABCDE1234F" from documents
    When I visit the new investor KYC page
    And I select "DocWizardInvestor" as the investor for the KYC
    And I upload "pan_card.pdf" for the Tax ID document field
    And I upload "address_proof.pdf" for the Address Proof document field
    And I submit the doc-first upload form
    Then I should see "Fields pre-filled from your documents"

  # ─────────────────────────────────────────────────────────────────────────────
  # 4. Investor magic link: doc-first wizard shows before the KYC form
  # ─────────────────────────────────────────────────────────────────────────────

  @doc_wizard_magic_link
  Scenario: Investor opens magic link and sees the doc-first upload form first
    Given there is a KYC for the investor with submission_status "link_sent"
    When I open the KYC edit page as the investor via a valid signed link
    Then I should see "Upload KYC Documents"
    And I should see "Upload PAN / Tax ID"
    And I should see "Upload Address Proof"

  # ─────────────────────────────────────────────────────────────────────────────
  # 5. Investor magic link: full wizard flow — upload docs → extraction → pre-filled form
  # ─────────────────────────────────────────────────────────────────────────────

  @doc_wizard_magic_link
  Scenario: Investor uploads documents via magic link and sees a pre-filled KYC form
    Given there is a KYC for the investor with submission_status "link_sent"
    And the LLM will extract "ABCDE1234F" from documents
    When I open the KYC edit page as the investor via a valid signed link
    And I upload "pan_card.pdf" for the Tax ID document field
    And I upload "address_proof.pdf" for the Address Proof document field
    And I submit the doc-first upload form via magic link
    Then I should see "Fields pre-filled from your documents"
    And I should see a "Save Draft" button
    # Below button now only shows on the last page
    # And I should see a "Submit KYC" button
    Then I click on "Next"
    Then I click on "Next"
    And I should see a "Submit KYC" button

  # ─────────────────────────────────────────────────────────────────────────────
  # 6. Submitting the upload form with no files does not start extraction
  #    (it used to bounce processing → edit → upload form forever)
  # ─────────────────────────────────────────────────────────────────────────────

  @doc_wizard
  Scenario: Company admin submits the doc-first form without files and is sent back to upload
    When I visit the new investor KYC page
    And I select "DocWizardInvestor" as the investor for the KYC
    And I click on "Continue to Fill Form →"
    Then I should see "Upload at least one document, or choose Fill Form Manually."
    And I should see "Upload KYC Documents"
    And no KYC document extraction should have been started

  @doc_wizard_magic_link
  Scenario: Investor submits the doc-first form without files via magic link and is sent back to upload
    Given there is a KYC for the investor with submission_status "link_sent"
    When I open the KYC edit page as the investor via a valid signed link
    And I click on "Continue to Fill Form →"
    Then I should see "Upload at least one document, or choose Fill Form Manually."
    And I should see "Upload KYC Documents"
    And no KYC document extraction should have been started
