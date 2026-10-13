@notification
Feature: Fund Commitment Adhoc Notification
  As a GP admin I want to send a custom adhoc notification
  to all or a selected subset of fund commitment holders

  @rack_test
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

  @rack_test
  Scenario: Notification is cc'd to the commitment's cc address
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And Given the commitments have a cc "advisor@gmail.com"
    Given there is an adhoc custom notification for the fund with subject "Q4 Update"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email cc'd to "advisor@gmail.com"

  @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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
    And the notification email attachment "Company Letter" is password protected with password "adhoc_fund_notification"

  @attachment @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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

  # Regression, first half: a document saved with stray whitespace in its name — which is what a
  # template named "SOA " produced, since DocumentGeneratorBase#upload interpolates the template
  # name — is stored squished by Document's `normalizes :name`. So a single-spaced attachment_names
  # entry finds it. HTML collapses the run, so before this the document looked like an exact match
  # in the UI while a literal LIKE missed it entirely.
  @attachment @rack_test
  Scenario: A document saved with a doubled space is stored squished and still attaches
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "SOA  01 April,2024 to 30 June,2024 - Demo Investor" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "\"SOA 01 April,2024 to 30 June,2024 - *\""
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has 1 documents attached

  # Regression, second half: the same tolerance from the other direction — the admin types or
  # pastes attachment_names with a doubled space against a clean document name. Deliberately a
  # WILDCARD entry: the exact-match branch goes through where(name:), which Rails' `normalizes`
  # already squishes, so only the raw-SQL "name like ?" branch actually exercises the squish in
  # documents_matching_attachment_name.
  @attachment @rack_test
  Scenario: A wildcard attachment_names entry typed with extra spaces still matches
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "Statement of Account" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement  of  Acc*"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has 1 documents attached

  # Same on the attachment_mandatory path, where a miss is far more costly: it suppresses the
  # whole email rather than just dropping the attachment.
  @attachment @rack_test
  Scenario: Attachment Mandatory sends when the entry differs only by extra whitespace
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "Statement of Account" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement  of  Account" and attachment_mandatory "true"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has 1 documents attached

  # Squishing collapses whitespace RUNS; it must not drop words. Without a '*' the entry is still
  # an exact match, so a missing word means no attachment rather than a loose partial match.
  @attachment @rack_test
  Scenario: An exact attachment name does not match a document with extra words in it
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "Statement of Account" with file "sample_kyc1.pdf"
    Given there is an adhoc custom notification for the fund with subject "Statement Ready" and attachment_names "Statement Account"
    When the adhoc notification is triggered for all commitments
    Then all commitment investors receive the notification email
    And the notification email has 0 documents attached

  @attachment @rack_test
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
    And the preview does not report anything over the size limit

  # Preview is where an admin answers "will this attach the right file?", and an oversized
  # document is silently refused at attach time - so without an explicit warning the preview
  # shows an empty attachment list, identical to a pattern that matched nothing. The admin
  # would go looking for a naming problem that does not exist.
  @attachment @rack_test
  Scenario: Preview reports a document that is too large to attach
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has an oversized document "Annual Report" of 20 MB
    Given there is an adhoc custom notification for the fund with subject "Annual Report" and attachment_names "Annual Report"
    When I open the actions menu on the first capital commitment
    When I click the preview adhoc notification button for "Annual Report"
    Then I see the adhoc notification preview with subject "Annual Report"
    And I see "Annual Report" reported in the preview as over the size limit
    And I see no attachments listed in the preview

  # The RUNNING TOTAL half of the rule, in the preview. No single file breaches the limit, so a
  # per-document check reports nothing at all here - the preview would show two attachments, a
  # third silently missing, and no explanation. This is the case the first version of the
  # preview warning got wrong.
  @attachment @rack_test
  Scenario: Preview reports documents that together exceed the size limit
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has 3 documents of 3 MB each named "Quarterly Pack"
    Given there is an adhoc custom notification for the fund with subject "Quarterly Pack" and attachment_names "Quarterly Pack*" and latest_doc_only "false"
    When I open the actions menu on the first capital commitment
    When I click the preview adhoc notification button for "Quarterly Pack"
    Then I see the adhoc notification preview with subject "Quarterly Pack"
    And I see the preview report something over the size limit
    # Two of the three fit and must still be listed - the guard drops only what tips the total.
    And I see 2 attachments listed in the preview

  @rack_test
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

  @rack_test
  Scenario: Investor KYC mode notification is cc'd to every shared commitment's cc address
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given the first two commitments share the same investor kyc
    And the first two commitments have ccs "advisor1@gmail.com" and "advisor2@gmail.com"
    Given there is an adhoc custom notification for the fund with subject "KYC Update" and attachment_names "" and notify_via "investor_kyc"
    When the adhoc notification is triggered for all investor kycs
    Then the investor kyc notification email is cc'd to "advisor1@gmail.com"
    And the investor kyc notification email is cc'd to "advisor2@gmail.com"

  @rack_test
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

  @rack_test
  Scenario: KYC notification placeholders are resolved correctly
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given the first two commitments share the same investor kyc
    And the shared investor kyc has full name "Recorded Legal Name"
    Given there is an adhoc kyc custom notification for the fund with placeholders and subject "KYC Placeholder Test"
    When the adhoc notification is triggered for all investor kycs
    Then the investor kyc notification placeholders are resolved correctly

  @rack_test
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

  @rack_test
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

  @rack_test
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

  @rack_test
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

  @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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

  @attachment @rack_test
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

  # Attachment size limit — NotificationAttachmentPreflight::MAX_ATTACHMENT_BYTES (7 MB).
  # A 20.3 MB PDF sent to 137 investors in Sep 2026 left at ~28 MB per message once
  # MIME-encoded and roughly nine in ten deliveries bounced, while the app recorded
  # every one as "Sent". See
  # docs/operations/troubleshooting/24092026_peercapital_annual_report_email_bounces.md
  #
  # Note what is asserted: the FIRST commitment's document is well within the limit, and it
  # still receives nothing. That is the whole point of preflighting the batch — one investor's
  # oversized document stops the run for everyone, rather than half the list receiving the
  # notification and the rest silently not.
  @attachment @rack_test
  Scenario: One oversized document stops the send for every recipient, not just that one
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "Annual Report" with file "sample_kyc1.pdf"
    And the second commitment has an oversized document "Annual Report" of 20 MB
    Given there is an adhoc custom notification for the fund with subject "Annual Report" and attachment_names "Annual Report"
    And in-app alerts are captured
    # "by the admin" because an in-app alert needs someone to send it to - FundsController always
    # passes current_user.id. The plain trigger step has no user on purpose (see its definition).
    When the adhoc notification is triggered by the admin for all commitments
    Then no commitment investor receives a notification email
    And the triggering user gets a danger in-app alert mentioning "over the 7 MB limit"
    And the user receives an email with "not sent" in the subject
    # The operator has to be able to ACT on this email, which means two things the earlier
    # version of the message left out. It must name whose document is oversized - "Annual
    # Report is 20 MB" is unusable on a 137-investor send when only one of them is at fault -
    # and it must say that the investors NOT named got nothing either. Without the second
    # sentence the email reads as "one investor failed", and nothing else corrects that: a
    # batch blocked before it starts writes no Noticed::Notification, so the notifications
    # list shows neither a sent nor a skipped row for the investors who were fine.
    And the blocked-send email names the second commitment investor
    # The email reports this as a table - which email, which investor, which document, how big,
    # why - because the single-paragraph version it replaced was unreadable once more than one
    # recipient was involved.
    And the email body should contain "Investor / Folio"
    And the email body should contain "Annual Report"
    And the email body should contain "20 MB"
    And the email body should contain "Larger than the 7 MB limit for one attachment"
    And the email body should contain "NO emails were sent - the entire send was stopped"
    And the email body should contain "1 recipient whose attachments were within the limit"
    # Client-facing: their own admin triggered this, so the support-facing diagnostic header
    # (host, environment, triggered-by) must not be in it.
    And the email body should not contain "Environment"

  # THE CASE THIS MISSED IN PRACTICE.
  #
  # The preflight deliberately skips commitments nobody would be emailed for - otherwise one
  # dormant commitment holding a large document would block the notification for every other
  # investor in the fund. The consequence is easy to misread as a broken limit: an oversized
  # document sitting on a commitment with no recipients does NOT stop the send, and the
  # investors who do have recipients are emailed normally. That is correct, and it needs to
  # stay correct - the alternative is a single dead commitment silencing a whole fund.
  @attachment @rack_test
  Scenario: A commitment nobody would be emailed for does not block the send for everyone else
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is an existing investor "" with "0" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "Annual Report" with file "sample_kyc1.pdf"
    And the second commitment has an oversized document "Annual Report" of 20 MB
    Given there is an adhoc custom notification for the fund with subject "Annual Report" and attachment_names "Annual Report"
    When the adhoc notification is triggered for all commitments
    Then the second commitment has no notification recipients
    And the first commitment investor receives the notification email
    And the notification email has the document "Annual Report" attached

  # The counterpart, so the two cannot be confused: the SAME oversized document on a
  # commitment that does have recipients stops the run for everyone.
  @attachment @rack_test
  Scenario: An oversized document on a commitment with recipients blocks the whole send
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the first commitment has document "Annual Report" with file "sample_kyc1.pdf"
    And the second commitment has an oversized document "Annual Report" of 20 MB
    Given there is an adhoc custom notification for the fund with subject "Annual Report" and attachment_names "Annual Report"
    When the adhoc notification is triggered for all commitments
    Then no commitment investor receives a notification email
    And the user receives an email with "not sent" in the subject
    And the blocked-send email names the second commitment investor
    And the email body should contain "NO emails were sent - the entire send was stopped"

  # A document attached to the NOTIFICATION rather than to a commitment goes to every
  # recipient identically, so one oversized one stops the run regardless of who is on it.
  @attachment
  Scenario: An oversized document on the notification itself stops the send
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    Given there is an adhoc custom notification for the fund with subject "Quarterly Pack"
    And the custom notification has an oversized document "Quarterly Pack" of 20 MB
    When the adhoc notification is triggered for all commitments
    Then no commitment investor receives a notification email
    And the user receives an email with "not sent" in the subject
    # Every recipient is affected here, since the document hangs off the notification rather
    # than off one commitment - so there is no "whose attachments were fine" clause to add,
    # and the message must not invent one.
    And the email body should contain "NO emails were sent - the entire send was stopped."
    And the email body should not contain "within the limit"

  # The running-total half of the guard: no single document breaches the limit, but the
  # message they would produce together does. A per-document check alone would send this.
  @attachment @rack_test
  Scenario: Several documents that individually fit but together exceed the limit are not emailed
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing investor "" with "1" users
    Given there is an existing investor "" with "1" users
    Given there is a fund "name=SAAS Fund" for the entity
    Given the investors are added to the fund
    Given there are capital commitments of "orig_folio_committed_amount_cents=100000000" from each investor
    And the second commitment has 3 documents of 3 MB each named "Quarterly Pack"
    Given there is an adhoc custom notification for the fund with subject "Quarterly Pack" and attachment_names "Quarterly Pack*" and latest_doc_only "false"
    When the adhoc notification is triggered for all commitments
    Then no commitment investor receives a notification email
    And the user receives an email with "not sent" in the subject
    And the blocked-send email names the second commitment investor
    # The running-total rule reports the total reached, not just the one document's size -
    # otherwise a table row reading "3 MB" against a "7 MB" limit looks like a false positive.
    And the email body should contain "Together with the other attachments this email reaches"
    And the email body should contain "over the 7 MB limit for one email"
    And the email body should contain "NO emails were sent - the entire send was stopped"

  # Regression guard on the size check itself — documents under the limit must be
  # completely unaffected. This is the common path for every client.
  @attachment @rack_test
  Scenario: A document under the size limit attaches and sends exactly as before
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
