@doc_gen
Feature: Zoho eSign

  Zoho-specific eSign behavior that isn't covered by the generic Digio/Docusign scenarios in
  doc_gen.feature: the expiry/reminder details shown on the document page, and extending an
  already-sent request's expiry - including rejecting a tampered/invalid date instead of
  raising a 500 (params can be tampered with even though the UI only offers a date picker).

Background:
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is an existing investor "entity_type=Family Office"
  Given there is an existing investor entity "entity_type=Investor Advisor" with employee "first_name=Advisor555"
  Given there is a fund "name=Test fundzoho1" for the entity
  And another user is "yes" fund advisor access to the fund
  And the access right has access "show,edit,update,destroy"
  Given the user has role "investor"
  Given the esign provider is "Zoho"
  Given the fund has capital commitments from each investor
  And each Investor has an approved Investor Kyc
  Given the fund has a template "Investor Statement Template" of type "Investor Statement Template"
  And we Generate Investor Statement for the first capital commitment
  Then the "Investor Statement Template" is successfully generated
  Then when the document is approved

Scenario: Document show page displays the Zoho eSignature expiry and reminder details
  And the document has "2" e_signatures by Zoho
  Then the document shows its Zoho eSignature expiry and reminder details

Scenario: Extending the Zoho eSignature expiry with a valid date updates the document
  And the document has "2" e_signatures by Zoho
  Then the Zoho eSignature expiry is extended to a valid future date

Scenario: Extending the Zoho eSignature expiry rejects a tampered, invalid date
  And the document has "2" e_signatures by Zoho
  Then extending the Zoho eSignature expiry with an invalid date is rejected without raising

Scenario: Sending a document for Zoho eSign includes the configured expiration and reminder settings
  Given the document's Zoho expiration is set to "30" days with reminders every "7" days
  When the document is sent for Zoho eSign
  Then the Zoho eSign request includes an expiration of "30" days and reminders every "7" days

Scenario: The document is partially signed via Zoho
  And the document has "2" e_signatures by Zoho
  Then the document is partially signed via Zoho

Scenario: The Zoho eSign completes and the completion certificate is attached
  And the document has "2" e_signatures by Zoho
  Then the document is signed by Zoho and the completion certificate is attached

Scenario: A Zoho eSign webhook reports a signer as signed
  And the document has "2" e_signatures by Zoho
  When a Zoho eSign webhook reports the first signer as signed
  Then the first signer's status is updated to signed and the second signer remains pending
