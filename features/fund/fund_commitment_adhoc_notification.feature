@notification
Feature: Fund Commitment Adhoc Notification
  As a GP admin I want to send a custom adhoc notification
  to all or a selected subset of fund commitment holders

  Scenario: Send notification to all commitments when no selection is made
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Q4 Update"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email

  Scenario: Send notification to a selected commitment only
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Selected Investor Notice"
    When the adhoc notification is triggered for the first commitment only
    Then only the first commitment investor receives the notification email
    And the second commitment investor does not receive a notification email

  Scenario: Notification attaches commitment document matching attachment_names
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "Statement of Account" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement of Account"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has the document "Statement of Account" attached

  Scenario: Notification attachment is password protected when password_protect_attachment is enabled
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has an investor kyc with PAN "ABCDE1234F"
    And the first commitment has document "Statement of Account" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement of Account" and password_protect_attachment "true" and attachment_password "investor_kyc.PAN"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has the document "Statement of Account" attached
    And the notification email attachment "Statement of Account" is password protected with password "ABCDE1234F"

  Scenario: Notification attachment is not password protected when password_protect_attachment is disabled
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "Statement of Account" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement of Account"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has the document "Statement of Account" attached
    And the notification email attachment "Statement of Account" is not password protected

  Scenario: A document linked directly to the custom notification is also password protected
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and password_protect_attachment "true" and attachment_password "email_method"
    And the custom notification has document "Company Letter" with file "sample_kyc1.pdf"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has the document "Company Letter" attached
    And the notification email attachment "Company Letter" is password protected with password "adhoc_notification"

  Scenario: Notification attaches documents matching a wildcard attachment_names pattern
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "SOA_FundA_03_2026" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "SOA_*_03_2026"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has the document "SOA_FundA_03_2026" attached

  Scenario: Notification attaches every matching document when latest_doc_only is unchecked
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "SOA_FundA_03_2026" with file "sample_kyc1.pdf"
    And the first commitment has document "SOA_FundB_03_2026" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "SOA_*_03_2026" and latest_doc_only "false"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has 2 documents attached

  Scenario: Notification attaches only the newest wildcard match when latest_doc_only is checked
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "SOA_FundA_03_2026" with file "sample_kyc1.pdf" created 2 days ago
    And the first commitment has document "SOA_FundB_03_2026" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "SOA_*_03_2026" and latest_doc_only "true"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has 1 documents attached
    And the notification email has the document "SOA_FundB_03_2026" attached
    And the notification email does not have the document "SOA_FundA_03_2026" attached

  Scenario: Notification attaches every copy of an exact-name match when latest_doc_only is unchecked
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "Statement of Account" with file "sample_kyc1.pdf"
    And the first commitment has document "Statement of Account" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement of Account" and latest_doc_only "false"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has 2 documents attached

  Scenario: Notification reproduces old close-match behavior via a *text* wildcard pattern
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "Statement of Account v2 FINAL" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "*Statement of Account*"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has 1 documents attached
    And the notification email has the document "Statement of Account v2 FINAL" attached

  Scenario: Notification attaches a document whose name contains a comma when the pattern is quoted
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "SOA UNit 01 July,2025 to 31 December,2025 - AA Holdings LLP - ESF-AA" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "\"SOA UNit 01 July,2025 to 31 December,2025 - *\""
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has 1 documents attached
    And the notification email has the document "SOA UNit 01 July,2025 to 31 December,2025 - AA Holdings LLP - ESF-AA" attached

  Scenario: Notification attaches documents for a comma-separated list mixing a quoted comma-containing name with a plain name
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "SOA UNit 01 July,2025 to 31 December,2025 - AA Holdings LLP - ESF-AA" with file "sample_kyc1.pdf"
    And the first commitment has document "KYC Certificate" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "\"SOA UNit 01 July,2025 to 31 December,2025 - *\",KYC Certificate"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has 2 documents attached
    And the notification email has the document "SOA UNit 01 July,2025 to 31 December,2025 - AA Holdings LLP - ESF-AA" attached
    And the notification email has the document "KYC Certificate" attached

  Scenario: Notification sends successfully with zero attachments when attachment_names matches nothing
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Nonexistent Document"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has 0 documents attached

  Scenario: Preview shows the document that would be attached via attachment_names
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "SOA_FundA_03_2026" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "SOA_*_03_2026"
    When I open the actions menu on the first capital commitment
    When I click the preview adhoc notification button for "Statement Ready"
    Then I see the adhoc notification preview with subject "Statement Ready"
    And I see "SOA_FundA_03_2026" listed as an attachment in the preview

  Scenario: Notification in Investor KYC mode sends one combined email when commitments share a KYC
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given the first two commitments share the same investor kyc
    And the shared investor kyc has document "PAN Card" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "KYC Update" and attachment_names "PAN Card" and notify_via "investor_kyc"
    When the adhoc notification is triggered for all investor kycs
    Then exactly one notification email is sent for the shared investor kyc
    And the investor kyc notification email has the document "PAN Card" attached

  Scenario: Investor KYC mode honors the specific-KYC selection
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given the first two commitments share the same investor kyc
    Given there is an adhoc custom notification for the fund with subject "KYC Update" and attachment_names "" and notify_via "investor_kyc"
    When the adhoc notification is triggered for the shared investor kyc only
    Then exactly one notification email is sent for the shared investor kyc

  Scenario: GP admin can preview the fund's adhoc notification from a capital commitment
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Q4 Update"
    When I open the actions menu on the first capital commitment
    Then I see a preview adhoc notification button
    When I click the preview adhoc notification button for "Q4 Update"
    Then I see the adhoc notification preview with subject "Q4 Update"

  Scenario: GP admin can preview each adhoc notification when the fund has more than one defined
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Q4 Update"
    Given there is an adhoc custom notification for the fund with subject "Year End Wrap-up"
    When I open the actions menu on the first capital commitment
    Then I see 2 preview adhoc notification buttons
    When I click the preview adhoc notification button for "Year End Wrap-up"
    Then I see the adhoc notification preview with subject "Year End Wrap-up"

  Scenario: Preview button is hidden when the fund has no adhoc notification defined
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    When I open the actions menu on the first capital commitment
    Then I do not see a preview adhoc notification button

  Scenario: Placeholders are resolved in adhoc notification body
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with placeholders and subject "Placeholder Test"
    When the adhoc notification is triggered for all commitments
    Then the adhoc notification placeholders are resolved correctly

  Scenario: Notification shows a View Commitment link when show_details_link is enabled
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Q4 Update" and show_details_link "true"
    When the adhoc notification is triggered for all commitments
    Then the notification email contains a link to view the commitment

  Scenario: Notification hides the View Commitment link when show_details_link is disabled
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Q4 Update" and show_details_link "false"
    When the adhoc notification is triggered for all commitments
    Then the notification email does not contain a link to view the commitment

  Scenario: Investor KYC mode notification shows a View KYC link when show_details_link is enabled
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given the first two commitments share the same investor kyc
    Given there is an adhoc custom notification for the fund with subject "KYC Update" and notify_via "investor_kyc" and show_details_link "true"
    When the adhoc notification is triggered for all investor kycs
    Then the investor kyc notification email contains a link to view the kyc

  Scenario: Attachment Mandatory sends normally when the required document exists for every recipient
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "Statement of Account" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement of Account" and attachment_mandatory "true"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has the document "Statement of Account" attached

  Scenario: Attachment Mandatory skips only the recipient missing the required document
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "Statement of Account" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement of Account" and attachment_mandatory "true"
    When the adhoc notification is triggered for all commitments
    Then only the first commitment investor receives the notification email
    And the second commitment investor does not receive a notification email
    And the second commitment investor's notification is recorded as skipped with a reason mentioning "Statement of Account"

  Scenario: Attachment Mandatory flag off keeps today's behavior of sending with zero attachments
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement of Account" and attachment_mandatory "false"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has 0 documents attached

  Scenario: Attachment Mandatory sends normally when the matching document is generated and approved
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has a generated document "Statement of Account" with file "sample_kyc1.pdf" that is approved
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement of Account" and attachment_mandatory "true"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has the document "Statement of Account" attached

  Scenario: Attachment Mandatory treats an unapproved generated document as missing
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "Statement of Account" with file "sample_kyc1.pdf"
    And the second commitment has a generated document "Statement of Account" with file "sample_kyc1.pdf" that is not approved
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement of Account" and attachment_mandatory "true"
    When the adhoc notification is triggered for all commitments
    Then only the first commitment investor receives the notification email
    And the second commitment investor does not receive a notification email
    And the second commitment investor's notification is recorded as skipped with a reason mentioning "Statement of Account"

  Scenario: Skipped notification report emails the admin who triggered the send
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement of Account" and attachment_mandatory "true"
    When the adhoc notification is triggered by the admin for all commitments
    And the skipped notification report runs
    Then the triggering admin receives a skipped notification report mentioning "Statement of Account"

  Scenario: Skipped notification report falls back to the entity's company admins when no admin triggered the send
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement of Account" and attachment_mandatory "true"
    When the adhoc notification is triggered for all commitments
    And the skipped notification report runs
    Then the entity's company admins receive a skipped notification report mentioning "Statement of Account"

  Scenario: Adhoc notification with a blank body is never sent, with no fallback message
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with a blank body and subject "Statement Ready"
    When the adhoc notification is triggered for all commitments
    Then no commitment investor receives a notification email
