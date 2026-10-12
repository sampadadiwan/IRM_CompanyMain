Feature: Evergreen dealing-date documents — contract notes and redemption advices from templates
  With a "Contract Note Template" / "Redemption Advice Template" a confirmed dealing date generates the
  documents (Generate documents) and an approver emails them (Approve & send); without one the investor
  is emailed straight away and the document steps do not apply.
  Worked examples H57–H62, E66–E70, E149, E150, E224, E225, X26–X30, X91–X94 — openspec/changes/open-ended-funds/design.md#worked-examples

  Background:
    Given Im logged in as a user "first_name=Asha" for an entity "name=Caphive Demo;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the entity has evergreen funds switched on
    And there is an approver "Ravi" in the entity
    And today is "2026-09-01"
    And the evergreen fund "Alpha Long-Short Fund" with classes "A" and settings "redemption_calendar=monthly;gate_pct=5;gate_method=fifo"
    And "A Ltd" is an investor of the fund with a portal user
    And "B LLP" is an investor of the fund with a portal user
    And "P Family Trust" is an investor of the fund with a portal user
    And "A Ltd" holds "12000" units of class "A" in folio "F-012" issued "2025-09-01"
    And "B LLP" holds "7000" units of class "A" in folio "F-031" issued "2025-09-01"
    And "Others" holds "81000" units of class "A" in folio "F-099" issued "2025-09-01"
    And an approved NAV for class "A" on "2026-08-31" with NAV per unit "10,000" and units "100000"

  # H57 — Happy path: with both templates, Generate documents builds one unapproved document per settled order (1 contract note, 2 advices) and emails no investor yet.
  @rack_test
  Scenario: Generate documents from templates
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And today is "2026-11-10"
    And I mark the redemption of "A Ltd" paid on "2026-11-10" with reference "UTR-A" in the tracker of "2026-11-02"
    And today is "2026-11-12"
    And I mark the redemption of "B LLP" paid on "2026-11-12" with reference "UTR-B" in the tracker of "2026-11-02"
    When I open the dealing date "2026-11-02"
    Then the step bar should show:
      | mark | task               |
      | ✓    | Allot units        |
      | ✓    | Pay redemptions    |
      | ✓    | Cancel units       |
      | ●    | Generate documents |
    When I click Generate documents on the dealing date "2026-11-02"
    Then I should see "Generating 3 documents — you'll be notified when they are ready"
    And the dealing date "2026-11-02" should have these documents:
      | investor       | folio | template                | approved |
      | P Family Trust | F-101 | Alpha Contract Note     | false    |
      | A Ltd          | F-012 | Alpha Redemption Advice | false    |
      | B LLP          | F-031 | Alpha Redemption Advice | false    |
    And no contract note or redemption advice email should have gone to investors
    And I should get the job alert "3 documents generated for 02/11/2026 — approve and send them on the dealing date"
    When I open the dealing date "2026-11-02"
    Then the step bar should show:
      | mark | task                       |
      | ✓    | Generate documents         |
      | ●    | Approve and send documents |

  # H58 — Happy path: once documents are generated every approver gets one "documents awaiting approval" alert naming the counts.
  @rack_test
  Scenario: Approvers are told documents await approval
    Given "Asha" is also an approver
    And the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    And the redemption of "B LLP" on "2026-11-02" was marked paid on "2026-11-12"
    When the documents of dealing date "2026-11-02" were generated
    Then "Ravi" should get one documents awaiting approval alert for "2026-11-02" saying:
      | 1 contract note and 2 redemption advices to approve |
      | Open the dealing date and click Approve & send      |
    And "Asha" should get one documents awaiting approval alert for "2026-11-02" saying:
      | 1 contract note and 2 redemption advices to approve |
      | Open the dealing date and click Approve & send      |

  # H59 — Happy path: an approver's Approve & send approves all three documents, emails each investor with the PDF and lets the date close.
  Scenario: Approve and send
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    And the redemption of "B LLP" on "2026-11-02" was marked paid on "2026-11-12"
    And the documents of dealing date "2026-11-02" were generated
    When the approver logs in
    And I click Approve & send on the dealing date "2026-11-02"
    Then the approve popup should say "1 contract note and 2 redemption advices"
    And the approve popup should say "Email investors"
    When I proceed in the confirm popup
    Then I should see "3 documents approved and sent"
    And the documents of dealing date "2026-11-02" should be approved by "Ravi"
    And "P Family Trust" should get the "contract note" email with the PDF attached
    And "A Ltd" should get the "redemption advice" email with the PDF attached
    And "B LLP" should get the "redemption advice" email with the PDF attached
    And every settled order of dealing date "2026-11-02" should have its email sent
    And the tracker row of "P Family Trust" on "2026-11-02" should read "Contract note sent"
    And the tracker row of "A Ltd" on "2026-11-02" should read "Redemption advice sent"
    And the tracker row of "B LLP" on "2026-11-02" should read "Redemption advice sent"
    And the step bar should show:
      | mark | task                       |
      | ✓    | Approve and send documents |
      | ●    | Close dealing date         |
    And Close dealing date should be enabled

  # H60 — Edge case: a folio's own Contract Note Template overrides the fund template for that folio only.
  @rack_test
  Scenario: A folio template overrides the fund template
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And "P Family Trust" holds "1000" units of class "A" in folio "F-101" issued "2025-09-01"
    And folio "F-101" has its own "Contract Note Template" "Alpha Contract Note" from the file "Commitment Agreement Template2.docx"
    And today is "2026-11-20"
    And "P Family Trust" has placed a "subscription" order "folio=F-101;amount=10000000" received "2026-11-20 09:00"
    And "A Ltd" has placed a "subscription" order "folio=F-012;amount=10000000" received "2026-11-20 09:30"
    And "P Family Trust" has paid the subscription on "2026-11-25"
    And "A Ltd" has paid the subscription on "2026-11-25"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,000" and units "101000"
    And today is "2026-12-01"
    And the fund admin confirms dealing date "2026-12-01"
    When I click Generate documents on the dealing date "2026-12-01"
    Then I should see "Generating 2 documents"
    And the dealing date "2026-12-01" should have these documents:
      | investor       | folio | template            | template folio | approved |
      | P Family Trust | F-101 | Alpha Contract Note | F-101          | false    |
      | A Ltd          | F-012 | Alpha Contract Note |                | false    |

  # H61 — Edge case: with no templates the contract note and advices are emailed at allotment / payment without a PDF and the document steps are not applicable.
  @rack_test
  Scenario: No templates — emails at once and the document steps do not apply
    Given the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    Then "P Family Trust" should get the "contract note" email without an attachment
    And "A Ltd" should have been sent 0 "redemption advice" emails
    Given today is "2026-11-10"
    When I mark the redemption of "A Ltd" paid on "2026-11-10" with reference "UTR-A" in the tracker of "2026-11-02"
    Then "A Ltd" should get the "redemption advice" email without an attachment
    And "B LLP" should have been sent 0 "redemption advice" emails
    Given today is "2026-11-12"
    When I mark the redemption of "B LLP" paid on "2026-11-12" with reference "UTR-B" in the tracker of "2026-11-02"
    Then "B LLP" should get the "redemption advice" email without an attachment
    And no document should be stored on folio "F-101"
    And no document should be stored on folio "F-012"
    And no document should be stored on folio "F-031"
    When I open the dealing date "2026-11-02"
    Then the step "Generate documents" should be not applicable with "has no Contract Note or Redemption Advice template"
    And the step "Approve and send documents" should be not applicable with "has no Contract Note or Redemption Advice template"
    And the dealing date actions should offer neither Generate documents nor Approve & send
    And the step bar should show:
      | mark | task               |
      | ✓    | Cancel units       |
      | ●    | Close dealing date |
    And Close dealing date should be enabled

  # H62 — Edge case: Regenerate on an unapproved document replaces only that document with a new unapproved one from the corrected template.
  @rack_test
  Scenario: Regenerate a document while it is unapproved
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    And the redemption of "B LLP" on "2026-11-02" was marked paid on "2026-11-12"
    And the documents of dealing date "2026-11-02" were generated
    And the template "Alpha Redemption Advice" is corrected
    When I click Regenerate on the document of "B LLP" on "2026-11-02"
    Then I should see "Document regenerated"
    And the document of "B LLP" on "2026-11-02" should be replaced by a new unapproved one from "Alpha Redemption Advice"
    And the other documents of "2026-11-02" should be untouched

  # E66 — Edge case: with only a Contract Note Template the advice is emailed at payment while the contract note goes through Generate → Approve & send.
  Scenario: Only a contract-note template
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    Then "P Family Trust" should have been sent 0 "contract note" emails
    Given today is "2026-11-10"
    When I mark the redemption of "A Ltd" paid on "2026-11-10" with reference "UTR-A" in the tracker of "2026-11-02"
    Then "A Ltd" should get the "redemption advice" email without an attachment
    When I click Generate documents on the dealing date "2026-11-02"
    Then I should see "Generating 1 document"
    And the dealing date "2026-11-02" should have these documents:
      | investor       | folio | template            | approved |
      | P Family Trust | F-101 | Alpha Contract Note | false    |
    And only 1 document should have been generated on "2026-11-02"
    When the approver logs in
    And I click Approve & send on the dealing date "2026-11-02"
    Then the approve popup should say "1 contract note"
    And the approve popup should not mention "redemption advice"
    When I proceed in the confirm popup
    Then I should see "1 document approved and sent"
    And "P Family Trust" should get the "contract note" email with the PDF attached
    And the step "Generate documents" should apply
    And the step "Approve and send documents" should apply

  # E67 — Edge case: a re-run of Generate documents after a later payment picks up only the newly settled order and never re-sends the earlier one.
  Scenario: A re-run picks up only new settlements
    Given the fund setting has "payment_timing=after"
    And "Q Capital" is an investor of the fund with a portal user
    And the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And today is "2026-11-10"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-11-10 09:00"
    And "Q Capital" has placed a "subscription" order "amount=25000000" received "2026-11-10 10:00"
    And an approved NAV for class "A" on "2026-11-30" with NAV per unit "10,000" and units "100000"
    And today is "2026-12-01"
    And the fund admin confirms dealing date "2026-12-01"
    And today is "2026-12-03"
    And I record the payment of "P Family Trust" on "2026-12-03" in the tracker of "2026-12-01"
    And today is "2026-12-04"
    And the documents of dealing date "2026-12-01" were generated
    And "Ravi" approved and sent the documents of dealing date "2026-12-01"
    And "P Family Trust" should have been sent 1 "contract note" email
    And today is "2026-12-06"
    When I record the payment of "Q Capital" on "2026-12-06" in the tracker of "2026-12-01"
    And I open the dealing date "2026-12-01"
    Then the step bar should show:
      | mark | task               |
      | ●    | Generate documents |
    When I click Generate documents on the dealing date "2026-12-01"
    Then I should see "Generating 1 document"
    And the dealing date "2026-12-01" should have these documents:
      | investor  | folio | template            | approved |
      | Q Capital | F-102 | Alpha Contract Note | false    |
    When the approver logs in
    And I click Approve & send on the dealing date "2026-12-01"
    Then the approve popup should say "1 contract note"
    And the approve popup should not mention "redemption advice"
    When I proceed in the confirm popup
    Then I should see "1 document approved and sent"
    And "Q Capital" should get the "contract note" email with the PDF attached
    And "P Family Trust" should have been sent 1 "contract note" email

  # E68 — Edge case: with a Redemption Advice Template marking a redemption paid cancels units but sends no advice email ("Advice to generate").
  @rack_test
  Scenario: No advice email at payment when a template exists
    Given the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And today is "2026-11-10"
    When I mark the redemption of "A Ltd" paid on "2026-11-10" with reference "UTR-A" in the tracker of "2026-11-02"
    Then folio "F-012" should hold "9,064.5793" units
    And "A Ltd" should have been sent 0 "redemption advice" emails
    And the tracker row of "A Ltd" on "2026-11-02" should read "Paid"
    And the tracker row of "A Ltd" on "2026-11-02" should read "Units cancelled"
    And the tracker row of "A Ltd" on "2026-11-02" should read "Redemption advice to generate"

  # E69 — Edge case: investors cannot see generated documents in Documents or Transactions until they are approved and sent.
  @rack_test
  Scenario: Investors cannot see unapproved documents
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    And the redemption of "B LLP" on "2026-11-02" was marked paid on "2026-11-12"
    And the documents of dealing date "2026-11-02" were generated
    When "P Family Trust" logs in to the portal
    And I open the fund as an investor
    Then the investor tab "Documents" should not list the "contract note" of "P Family Trust" on "2026-11-02"
    And the investor tab "Transactions" should not list the "contract note" of "P Family Trust" on "2026-11-02"
    When "Ravi" approves and sends the documents of dealing date "2026-11-02"
    And I open the fund as an investor
    Then the investor tab "Documents" should list the "contract note" of "P Family Trust" on "2026-11-02"
    And the investor tab "Transactions" should list the "contract note" of "P Family Trust" on "2026-11-02"

  # E70 — Edge case: with the documents-awaiting-approval alert switched off documents are still generated but approvers get no alert.
  @rack_test
  Scenario: Documents awaiting approval switched off
    Given the fund has switched off the documents awaiting approval alert
    And the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    And the redemption of "B LLP" on "2026-11-02" was marked paid on "2026-11-12"
    When I click Generate documents on the dealing date "2026-11-02"
    Then I should see "Generating 3 documents"
    And the dealing date "2026-11-02" should have these documents:
      | investor       | folio | approved |
      | P Family Trust | F-101 | false    |
      | A Ltd          | F-012 | false    |
      | B LLP          | F-031 | false    |
    And "Ravi" should get no documents awaiting approval alert
    And I should get the job alert "3 documents generated for 02/11/2026"

  # X26 — Error case: a non-approver sees no Approve & send and a direct request is refused, leaving every document unapproved and unsent.
  @rack_test
  Scenario: Approve & send needs the approver role
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    And the redemption of "B LLP" on "2026-11-02" was marked paid on "2026-11-12"
    And the documents of dealing date "2026-11-02" were generated
    And the email queue is cleared
    When I open the dealing date "2026-11-02"
    Then the dealing date actions should not offer Approve & send
    When "Asha" posts "approve_documents" for dealing date "2026-11-02" directly
    Then the direct request should be refused
    And no document of dealing date "2026-11-02" should be approved
    And no contract note or redemption advice email should have gone to investors

  # X27 — Error case: an approved document offers no Regenerate and a direct request is refused with "Approved documents can't be regenerated".
  @rack_test
  Scenario: An approved document cannot be regenerated
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    And the redemption of "B LLP" on "2026-11-02" was marked paid on "2026-11-12"
    And the documents of dealing date "2026-11-02" were generated
    And "Ravi" approved and sent the documents of dealing date "2026-11-02"
    When I open the dealing date "2026-11-02"
    Then the tracker row of "P Family Trust" on "2026-11-02" should not offer Regenerate
    When "Asha" posts regenerate for the document of "P Family Trust" on "2026-11-02" directly
    Then the direct request should be refused with "Approved documents can't be regenerated"
    And the document of "P Family Trust" on "2026-11-02" should be unchanged

  # X28 — Error case: Close dealing date is disabled with "Send every contract note and redemption advice first" while generated documents are unsent.
  @rack_test
  Scenario: Close needs every document sent
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    And the redemption of "B LLP" on "2026-11-02" was marked paid on "2026-11-12"
    And the documents of dealing date "2026-11-02" were generated
    When I open the dealing date "2026-11-02"
    Then Close dealing date should be disabled with "Send every contract note and redemption advice first"

  # X29 — Error case: once every settled order's document is sent the dealing date offers no Generate documents and a direct request is refused with "Nothing to generate — every settled order already has its document or email", generating nothing.
  @rack_test
  Scenario: Nothing to generate
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    And the redemption of "B LLP" on "2026-11-02" was marked paid on "2026-11-12"
    And the documents of dealing date "2026-11-02" were generated
    And "Ravi" approved and sent the documents of dealing date "2026-11-02"
    When I open the dealing date "2026-11-02"
    Then the dealing date actions should not offer Generate documents
    When I note the generated documents
    And "Asha" posts "generate_documents" for dealing date "2026-11-02" directly
    Then the direct request should be refused with "Nothing to generate — every settled order already has its document or email"
    And no new document should have been generated
    And no job alert should have been sent

  # X30 — Error case: one document failing to generate leaves its row "Not generated" with Regenerate while the other two are generated and approvers are alerted.
  @rack_test
  Scenario: One document fails to generate
    Given "Asha" is also an approver
    And the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And folio "F-031" has its own "Redemption Advice Template" "Alpha Redemption Advice" from the file "Instructions.txt"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    And the redemption of "B LLP" on "2026-11-02" was marked paid on "2026-11-12"
    When I click Generate documents on the dealing date "2026-11-02"
    Then the dealing date "2026-11-02" should have these documents:
      | investor       | folio | approved |
      | P Family Trust | F-101 | false    |
      | A Ltd          | F-012 | false    |
    And "B LLP" on "2026-11-02" should have no document
    And I should get the job alert "2 documents generated for 02/11/2026"
    And the job alert should also say "1 failed: B LLP: "
    And "Ravi" should get one documents awaiting approval alert for "2026-11-02" saying:
      | 1 contract note and 1 redemption advice to approve |
    When I open the dealing date "2026-11-02"
    Then the step bar should show:
      | mark | task               |
      | ●    | Generate documents |
    And the tracker row of "B LLP" on "2026-11-02" should read "Not generated"
    And the tracker row of "B LLP" on "2026-11-02" should offer Regenerate

  # E149 — Edge case: with only a Redemption Advice Template the contract note is emailed at allotment without a PDF and Generate documents builds just the 2 advices.
  @rack_test
  Scenario: Only a redemption-advice template
    Given the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    Then "P Family Trust" should get the "contract note" email without an attachment
    Given the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    And the redemption of "B LLP" on "2026-11-02" was marked paid on "2026-11-12"
    Then "A Ltd" should have been sent 0 "redemption advice" emails
    When the documents of dealing date "2026-11-02" were generated
    Then only 2 documents should have been generated on "2026-11-02"
    And the dealing date "2026-11-02" should have these documents:
      | investor | folio | template                | approved |
      | A Ltd    | F-012 | Alpha Redemption Advice | false    |
      | B LLP    | F-031 | Alpha Redemption Advice | false    |
    And "P Family Trust" on "2026-11-02" should have no document

  # E150 — Edge case: running Generate documents twice (a double click or a re-queued job) still leaves exactly 3 documents — one per settled order, no duplicates.
  @rack_test
  Scenario: Generating twice makes no duplicate documents
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    And the redemption of "B LLP" on "2026-11-02" was marked paid on "2026-11-12"
    When the documents of dealing date "2026-11-02" were generated
    And the documents of dealing date "2026-11-02" were generated
    Then there should be exactly 3 generated documents in the fund
    And only 3 documents should have been generated on "2026-11-02"

  # X91 — Error case: Approve & send posted again after Ravi has already sent everything is refused with "No documents waiting for approval" and no investor gets a second email.
  @rack_test
  Scenario: Approve & send twice sends each document once
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    And the redemption of "B LLP" on "2026-11-02" was marked paid on "2026-11-12"
    And the documents of dealing date "2026-11-02" were generated
    And "Ravi" approved and sent the documents of dealing date "2026-11-02"
    When "Ravi" posts "approve_documents" for dealing date "2026-11-02" directly
    Then the direct request should be refused with "No documents waiting for approval"
    And "P Family Trust" should have been sent 1 "contract note" email
    And "A Ltd" should have been sent 1 "redemption advice" email
    And "B LLP" should have been sent 1 "redemption advice" email

  # X92 — Error case: Regenerate posted for B LLP's redemption before it is paid is refused — no advice is generated for units not yet cancelled.
  Scenario: No advice can be regenerated for an unpaid redemption
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    When "Asha" posts regenerate for the document of "B LLP" on "2026-11-02" directly
    Then the direct request should not say "Document regenerated"
    And "B LLP" on "2026-11-02" should have no document

  # X93 — Error case: Generate documents posted for a dealing date that is not yet confirmed is refused and nothing is generated.
  @rack_test
  Scenario: Documents cannot be generated before the dealing date is confirmed
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And I note the generated documents
    When "Asha" posts "generate_documents" for dealing date "2026-11-02" directly
    Then the direct request should be refused
    And no new document should have been generated
    And the dealing date "2026-11-02" should be "open"

  # X94 — Error case: Close dealing date posted directly while the generated documents are unsent is refused with "Finish settling this dealing date before closing it" and the date stays confirmed.
  @rack_test
  Scenario: A direct close is refused while documents are unsent
    Given the fund has the "Contract Note Template" "Alpha Contract Note"
    And the fund has the "Redemption Advice Template" "Alpha Redemption Advice"
    And the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And the redemption of "A Ltd" on "2026-11-02" was marked paid on "2026-11-10"
    And the redemption of "B LLP" on "2026-11-02" was marked paid on "2026-11-12"
    And the documents of dealing date "2026-11-02" were generated
    When "Asha" posts close for dealing date "2026-11-02" directly
    Then the direct request should be refused with "Finish settling this dealing date before closing it"
    And the dealing date "2026-11-02" should be "confirmed"

  # E224 — Edge case: a sent document's Resend is a button in the row's Actions column that asks first ("Immediate Actions": email the investor again; nothing else changes); the Settlement column shows only status badges.
  @rack_test
  Scenario: Resend is a button that asks first
    Given the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And today is "2026-11-10"
    When I mark the redemption of "A Ltd" paid on "2026-11-10" with reference "UTR-A" in the tracker of "2026-11-02"
    Then the tracker row of "A Ltd" on "2026-11-02" should read "Redemption advice sent"
    And the Resend of "A Ltd" on "2026-11-02" should be a button asking "Email A Ltd again"

  # E225 — Edge case: the order page says what dealing did to the folio next to the amount ("Units cancelled … at ₹… on …") and has a Dealing card with what the order got on each dealing date and the same settlement badges and buttons — Resend works from there too.
  @rack_test
  Scenario: The order page shows its dealing and can resend
    Given the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming
    And today is "2026-11-10"
    When I mark the redemption of "A Ltd" paid on "2026-11-10" with reference "UTR-A" in the tracker of "2026-11-02"
    And I open the "redemption" order of "A Ltd"
    Then the order's units dealt should read "Units cancelled"
    And the order page should link the investor, folio and dealing date
    And the order's dealing row for "2026-11-02" should read "Redemption advice sent"
    And the Resend of "A Ltd" on "2026-11-02" should be a button asking "Email A Ltd again"
