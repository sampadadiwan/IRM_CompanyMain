Feature: KYC Document Extractor Agent
  As a fund admin I want to configure a KycDocExtractorAgent so that uploaded investor documents
  are automatically parsed by an LLM and extracted values pre-populate the KYC form,
  reducing manual data entry for investors.

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=DocExtractFund;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing investor "investor_name=DocExtractInvestor1" with "1" users
    And the entity has kyc_doc_first_wizard enabled
    And there is a KycDocExtractorAgent configured for the entity

  # ─────────────────────────────────────────────────────────────────────────────
  # 1. SupportAgent setup
  # ─────────────────────────────────────────────────────────────────────────────

  @kyc_doc_extractor @agent_setup
  Scenario: KycDocExtractorAgent appears in the supported agent types list
    Then "KycDocExtractorAgent" is a recognised support agent type

  @kyc_doc_extractor @agent_setup
  Scenario: Fund admin can save extraction rules for a form type
    Given there is a KYC form type "IndividualKyc" for the entity
    When the fund admin saves extraction rules for the form type:
      | doc_label | prompt                           | target_field |
      | PAN Card  | Extract the PAN number.          | PAN          |
      | Address   | Extract the full street address. | address      |
    Then the KycDocExtractorAgent json_fields contains 2 rules for the form type

  # ─────────────────────────────────────────────────────────────────────────────
  # 2. Extract button appears on form when enabled
  # ─────────────────────────────────────────────────────────────────────────────

  @kyc_doc_extractor @form_ui
  Scenario: Doc-first upload screen is shown when wizard is enabled and no documents uploaded
    Given there is a KYC for the investor with submission_status "link_sent"
    When I visit the KYC edit page as the fund admin
    Then I should see "Upload KYC Documents"
    And I should see "Upload Tax ID"
    And I should see "Upload Address Proof"

  @kyc_doc_extractor @form_ui
  Scenario: Extract button is NOT shown when kyc_doc_first_wizard is disabled
    Given the entity has kyc_doc_first_wizard disabled
    And there is a KYC for the investor with submission_status "link_sent"
    When I visit the KYC edit page as the fund admin
    Then I should not see an "Extract from Documents" button

  @kyc_doc_extractor @form_ui
  Scenario: Extract button is NOT shown when KYC is already submitted
    Given there is a KYC for the investor with submission_status "completed"
    When I visit the KYC edit page as the fund admin
    Then I should not see an "Extract from Documents" button

  # ─────────────────────────────────────────────────────────────────────────────
  # 3. Agent extraction — blank_only mode
  # ─────────────────────────────────────────────────────────────────────────────

  @kyc_doc_extractor @extraction
  Scenario: Extraction fills blank fields from matching documents
    Given there is a KYC for the investor with submission_status "link_sent"
    And the KYC field "PAN" is blank
    And the KYC has an uploaded document "PAN Card"
    And the KycDocExtractorAgent has a rule: doc_label "PAN Card", prompt "Extract PAN", target_field "PAN"
    And the LLM returns "ABCDE1234F" for the extraction prompt
    When the fund admin triggers document extraction for the KYC
    Then the KYC field "PAN" is set to "ABCDE1234F"
    And the extraction result includes 1 extracted field

  @kyc_doc_extractor @extraction
  Scenario: Extraction skips fields that already have a value in blank_only mode
    Given there is a KYC for the investor with submission_status "link_sent"
    And the KYC has an uploaded document "PAN Card"
    And the KYC field "PAN" already has value "ZZZZZ9999Z"
    And the KycDocExtractorAgent overwrite_mode is "blank_only"
    And the KycDocExtractorAgent has a rule: doc_label "PAN Card", prompt "Extract PAN", target_field "PAN"
    When the fund admin triggers document extraction for the KYC
    Then the KYC field "PAN" remains "ZZZZZ9999Z"
    And the extraction result includes 0 extracted fields

  @kyc_doc_extractor @extraction
  Scenario: Extraction overwrites existing values when overwrite_mode is always
    Given there is a KYC for the investor with submission_status "link_sent"
    And the KYC has an uploaded document "PAN Card"
    And the KYC field "PAN" already has value "ZZZZZ9999Z"
    And the KycDocExtractorAgent overwrite_mode is "always"
    And the KycDocExtractorAgent has a rule: doc_label "PAN Card", prompt "Extract PAN", target_field "PAN"
    And the LLM returns "ABCDE1234F" for the extraction prompt
    When the fund admin triggers document extraction for the KYC
    Then the KYC field "PAN" is set to "ABCDE1234F"

  @kyc_doc_extractor @extraction
  Scenario: Extraction skips rules where the document has not been uploaded
    Given there is a KYC for the investor with submission_status "link_sent"
    And the KycDocExtractorAgent has a rule: doc_label "Passport", prompt "Extract passport number", target_field "passport_number"
    When the fund admin triggers document extraction for the KYC
    Then the extraction result includes 0 extracted fields
    And the extraction result includes 1 skipped rule

  # ─────────────────────────────────────────────────────────────────────────────
  # 4. Policy — only authorised users can trigger extraction
  # ─────────────────────────────────────────────────────────────────────────────

  @kyc_doc_extractor @policy
  Scenario: An investor via magic link sees the doc-first upload screen
    Given there is a KYC for the investor with submission_status "link_sent"
    When I open the KYC edit page as the investor via a valid signed link for doc extraction
    Then I should see "Upload KYC Documents"
    And I should see "Continue to Fill Form"

  @kyc_doc_extractor @policy
  Scenario: Agent not configured returns a redirect with an alert
    Given there is a KYC for the investor with submission_status "link_sent"
    And the entity has NO KycDocExtractorAgent configured
    When the fund admin triggers document extraction for the KYC
    Then the response redirects with an alert about missing agent configuration
