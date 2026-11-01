Feature: Core / misc medium findings - 2026-10 security review
  Fixes from the "Core / misc — Medium and Low" table. Each refusal is paired with the legitimate use
  that must keep working. Scenarios set up their own data (no shared Background), so findings can be
  added independently.
  Design and worked examples: docs/security/security_review_2026_10.md#core--misc--medium-and-low

  # ---- M7 chats ------------------------------------------------------------------------------

  # M7-1 — Edge case: a colleague who is not a company admin opens the company admin's assistant chat and its tool-call report by id
  @security @rack_test
  Scenario: M7-1 A colleague can't read another person's chat or its efficiency report
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Ravi" is a plain employee of "Alpha Capital"
    And "Priya" has an assistant chat asking "Summarise Q2 returns"
    And "Ravi" is signed in
    When they open "Priya"'s chat
    Then I am denied access
    And the response does not mention "Summarise Q2 returns"
    When they open the efficiency report of "Priya"'s chat
    Then I am denied access
    And the response does not mention "AI Tool Efficiency Report"

  # M7-2 — Edge case: the efficiency report of a chat id that does not exist is a 404, not a 500
  @security @rack_test
  Scenario: M7-2 A missing chat's efficiency report is not found
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Priya" is signed in
    When they open the efficiency report of a chat that does not exist
    Then the request is answered with not found

  # M7-H — Happy path: the asker opens their own chat and report; a company admin still reads an employee's chat (Decision)
  @security @rack_test
  Scenario: M7-H The asker sees their own chat and report, and the company admin sees an employee's chat
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Ravi" is a plain employee of "Alpha Capital"
    And "Ravi" has an assistant chat asking "Which LPs are overdue?"
    And "Ravi" is signed in
    When they open the efficiency report of "Ravi"'s chat
    Then the response mentions "AI Tool Efficiency Report"
    When they open "Ravi"'s chat
    Then the response mentions "Which LPs are overdue?"
    Given "Priya" is signed in
    When they open "Ravi"'s chat
    Then the response mentions "Which LPs are overdue?"

  # ---- M12 kanban ----------------------------------------------------------------------------

  # M12-1 — Edge case: another firm's employee loads my board through the board filter
  @security @rack_test
  Scenario: M12-1 Another firm can't open my board through the card filter
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has a kanban board "Alpha Secret Pipeline" with a card "Call Acme Ventures"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Omar" is signed in
    When they filter the board "Alpha Secret Pipeline"
    Then I am denied access
    And the response does not mention "Alpha Secret Pipeline"

  # M12-2 — Edge case: another firm's employee opens my board through the card search, which lists every card
  @security @rack_test
  Scenario: M12-2 Another firm can't open my board through the card search
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has a kanban board "Alpha Secret Pipeline" with a card "Call Acme Ventures"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Omar" is signed in
    When they search the board "Alpha Secret Pipeline"
    Then I am denied access
    And the response does not mention "Call Acme Ventures"

  # M12-3 — Edge case: another firm's employee renders my board through the deal investor list's board view
  @security @rack_test
  Scenario: M12-3 Another firm can't open my board through the deal investor list
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has a kanban board "Alpha Secret Pipeline" with a card "Call Acme Ventures"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Omar" is signed in
    When they list deal investors on the board "Alpha Secret Pipeline"
    Then I am denied access
    And the response does not mention "Alpha Secret Pipeline"

  # M12-H — Happy path: the firm's own employee filters and searches their board
  @security @rack_test
  Scenario: M12-H The firm's employee filters and searches their own board
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has a kanban board "Alpha Pipeline" with a card "Call Acme Ventures"
    And "Ravi" is a plain employee of "Alpha Capital"
    And "Ravi" is signed in
    When they filter the board "Alpha Pipeline"
    Then the response mentions "Call Acme Ventures"
    When they search the board "Alpha Pipeline"
    Then the response mentions "Call Acme Ventures"

  # ---- M13 NDA -------------------------------------------------------------------------------

  # M13-1 — Edge case: a GP removes another firm's NDA signatory by id through their own NDA config
  @security @rack_test
  Scenario: M13-1 A signatory of another firm's NDA can't be removed through my NDA
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has a data room NDA with signatory "Lena"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Zeta Partners" has a data room NDA with signatory "Kofi"
    And "Priya" is signed in
    When they remove the signatory "Kofi" through the NDA of "Alpha Capital"
    Then I am denied access
    And "Kofi" is still a signatory of the NDA of "Zeta Partners"

  # M13-2 — Edge case: a GP opens their NDA's status summary with another firm's folder id
  @security @rack_test
  Scenario: M13-2 My NDA's status can't be listed over another firm's folder
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has a data room NDA with signatory "Lena"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Zeta Partners" has a data room NDA with signatory "Kofi"
    And "Priya" is signed in
    When they open the NDA status summary of "Alpha Capital" for the data room of "Zeta Partners"
    Then I am denied access

  # M13-H — Happy path: the GP untags their own NDA's signatory and opens its status summary
  @security @rack_test
  Scenario: M13-H The GP removes their own NDA's signatory and sees its status
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has a data room NDA with signatory "Lena"
    And "Priya" is signed in
    When they remove the signatory "Lena" through the NDA of "Alpha Capital"
    Then the page loads
    And "Lena" is no longer a signatory of the NDA of "Alpha Capital"
    When they open the NDA status summary of "Alpha Capital" for the data room of "Alpha Capital"
    Then the page loads

  # ---- M14 nudges ----------------------------------------------------------------------------

  # M14-1 — Edge case: another firm's GP opens the nudge form for my deal investor, which would prefill its LP emails
  @security @rack_test
  Scenario: M14-1 Another firm's nudge form shows none of my LP emails
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has a deal investor "Acme Ventures" whose LP contact is "lp.contact@acme-ventures.example"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Omar" is signed in
    When they open a new nudge for the deal investor "Acme Ventures"
    Then I am denied access
    And the response does not mention "lp.contact@acme-ventures.example"

  # M14-H — Happy path: the deal's own GP gets the LP emails prefilled (the Decision kept the prefill)
  @security @rack_test
  Scenario: M14-H The firm's GP gets the LP contact prefilled on a nudge
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has a deal investor "Acme Ventures" whose LP contact is "lp.contact@acme-ventures.example"
    And "Priya" is signed in
    When they open a new nudge for the deal investor "Acme Ventures"
    Then the response mentions "lp.contact@acme-ventures.example"

  # ---- M15 write before authorize ------------------------------------------------------------

  # M15-1 — Edge case: an employee without the kanban permission posts the New Board form; nothing is saved
  @security @rack_test
  Scenario: M15-1 A refused board is never saved
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Ravi" is a plain employee of "Alpha Capital" without the kanban permission
    And "Ravi" is signed in
    When they create a board "Ravi Board"
    Then I am denied access
    And there is no board "Ravi Board"

  # M15-2 — Edge case: the New Board form names another firm; the board is made in the user's own firm
  @security @rack_test
  Scenario: M15-2 A board posted for another firm lands in the user's own firm
    Given the firm "Alpha Capital" with company admin "Priya"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Priya" is signed in
    When they create a board "Planted Board" for the firm "Zeta Partners"
    Then the board "Planted Board" belongs to "Alpha Capital"

  # M15-3 — Edge case: another firm's company admin adds a grid column to my firm's form type; nothing is saved
  @security @rack_test
  Scenario: M15-3 Another firm can't add a grid column to my form type
    Given the firm "Alpha Capital" with company admin "Priya"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Omar" is signed in
    When they add the grid column "folio_id" to the "CapitalCommitment" form type of "Alpha Capital"
    Then I am denied access
    And the "CapitalCommitment" form type of "Alpha Capital" has 0 grid columns

  # M15-4 — Edge case: another firm's user opens Configure Grid for my firm's form type
  @security @rack_test
  Scenario: M15-4 Another firm can't open Configure Grid for my form type
    Given the firm "Alpha Capital" with company admin "Priya"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Omar" is signed in
    When they open Configure Grid for the "CapitalCommitment" form type of "Alpha Capital"
    Then I am denied access

  # M15-H — Happy path: the firm's admin makes a board and adds a column; a non-admin colleague opens Configure Grid (Decision)
  @security @rack_test
  Scenario: M15-H The firm's admin creates a board and a grid column, and a colleague opens Configure Grid
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Ravi" is a plain employee of "Alpha Capital"
    And "Priya" is signed in
    When they create a board "Alpha Pipeline"
    Then the board "Alpha Pipeline" belongs to "Alpha Capital"
    When they add the grid column "folio_id" to the "CapitalCommitment" form type of "Alpha Capital"
    Then the "CapitalCommitment" form type of "Alpha Capital" has 1 grid column
    Given "Ravi" is signed in
    When they open Configure Grid for the "CapitalCommitment" form type of "Alpha Capital"
    Then the page loads

  # ---- M17 Permission ------------------------------------------------------------------------

  # M17-1 — Edge case: an employee who can't change a document grants themselves write on it
  @security @rack_test
  Scenario: M17-1 An employee can't grant themselves write on a document
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Ravi" is a plain employee of "Alpha Capital"
    And "Alpha Capital" has a document "Side Letter"
    And "Ravi" is signed in
    When they grant "Ravi" write on the document "Side Letter"
    Then I am denied access
    And "Ravi" has no permission on the document "Side Letter"
    And "Ravi" cannot change the document "Side Letter"

  # M17-2 — Edge case: a colleague who can't change the document opens a grant someone else made on it
  @security @rack_test
  Scenario: M17-2 A colleague can't open another person's grant on a document they can't change
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Ravi" is a plain employee of "Alpha Capital"
    And "Mina" is a plain employee of "Alpha Capital"
    And "Alpha Capital" has a document "Side Letter"
    And "Priya" granted "Mina" read on the document "Side Letter"
    And "Ravi" is signed in
    When they open that permission
    Then I am denied access

  # M17-H — Happy path: the company admin grants an employee write, the employee can then change the document, and the admin opens the grant
  @security @rack_test
  Scenario: M17-H The company admin grants write on a document
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Ravi" is a plain employee of "Alpha Capital"
    And "Alpha Capital" has a document "Side Letter"
    And "Priya" is signed in
    When they grant "Ravi" write on the document "Side Letter"
    Then "Ravi" can change the document "Side Letter"
    Given "Priya" granted "Ravi" read on the document "Side Letter"
    When they open that permission
    Then the page loads

  # ---- M18 task templates --------------------------------------------------------------------

  # M18-1 — Edge case: a company admin writes a global template (no firm), which would reach every firm's generated tasks
  @security @rack_test
  Scenario: M18-1 Only support writes a global task template
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Priya" is signed in
    When they create a "CapitalCall" task template "Wire to account 123" for no firm
    Then I am denied access
    And there is no task template "Wire to account 123"

  # M18-2 — Edge case: another firm's company admin rewrites my firm's template
  @security @rack_test
  Scenario: M18-2 Another firm can't change my firm's task template
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has a "CapitalCall" task template "Collect the call notice"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Omar" is signed in
    When they change the task template "Collect the call notice" to "Pay into the new account"
    Then I am denied access
    And there is no task template "Pay into the new account"

  # M18-3 — Edge case: another firm's template is neither opened by me nor used for my firm's next steps
  @security @rack_test
  Scenario: M18-3 Another firm's task template stays in that firm
    Given the firm "Alpha Capital" with company admin "Priya"
    And the firm "Zeta Partners" with company admin "Omar"
    And there is a global "CapitalCall" task template "Send the call notice"
    And "Alpha Capital" has a "CapitalCall" task template "Collect the call notice"
    And "Zeta Partners" has a "CapitalCall" task template "Zeta only step"
    And "Priya" is signed in
    When they open the task template "Zeta only step"
    Then I am denied access
    And next steps for a "CapitalCall" of "Alpha Capital" are "Send the call notice, Collect the call notice"

  # M18-4 — Edge case: a help link that is not a web address (it renders as a link on every task)
  @security
  Scenario: M18-4 A task template's help link must be an http(s) address
    Then a task template with help link "javascript:alert(document.cookie)" is refused
    And a task template with help link "data:text/html,<script>alert(1)</script>" is refused
    And a task template with help link "https://help.example.com/capital-calls" is accepted

  # M18-H — Happy path: a company admin writes their own firm's template; support writes a global one
  @security @rack_test
  Scenario: M18-H Company admins write their firm's templates and support writes global ones
    Given the firm "Alpha Capital" with company admin "Priya"
    And the firm "CapHive Ops" with company admin "Olga"
    And "Sam" is a support user and company admin of "CapHive Ops"
    And "Priya" is signed in
    When they create a "CapitalCall" task template "Check the bank details" for "Alpha Capital"
    Then the task template "Check the bank details" belongs to "Alpha Capital"
    Given "Sam" is signed in
    When they create a "CapitalCall" task template "Send the call notice" for no firm
    Then the task template "Send the call notice" is global
    And next steps for a "CapitalCall" of "Alpha Capital" are "Send the call notice, Check the bank details"

  # ---- M22 incoming email --------------------------------------------------------------------

  # M22-1 — Edge case: a GP files an email against another firm's investor through the plain create form
  @security @rack_test
  Scenario: M22-1 An email can't be filed against another firm's investor
    Given the firm "Alpha Capital" with company admin "Priya"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Zeta Partners" has an investor "Zeta Family Trust"
    And "Priya" is signed in
    When they file an email "Planted note" against the investor "Zeta Family Trust" through the plain form
    Then I am denied access
    And there is no incoming email "Planted note"

  # M22-2 — Edge case: an existing email is moved onto another firm's investor
  @security
  Scenario: M22-2 An email can't be moved onto another firm's investor
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has an investor "Acme Ventures"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Zeta Partners" has an investor "Zeta Family Trust"
    And "Alpha Capital" has an incoming email "Q3 update" against the investor "Acme Ventures"
    When the email "Q3 update" is moved onto the investor "Zeta Family Trust"
    Then the move is refused and "Q3 update" stays against the investor "Acme Ventures"

  # M22-H — Happy path: the GP files an email against their own investor from the investor page
  @security @rack_test
  Scenario: M22-H The GP files an email against their own investor
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has an investor "Acme Ventures"
    And "Priya" is signed in
    When they file an email "Q3 update" against the investor "Acme Ventures" from the investor page
    Then the incoming email "Q3 update" is filed in "Alpha Capital" against the investor "Acme Ventures"

  # ---- M25 form type clone -------------------------------------------------------------------

  # M25-1 — Edge case: the old GET clone address is gone, so a link or prefetch can't create a copy
  @security @rack_test
  Scenario: M25-1 The GET clone address is not found and copies nothing
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Sam" is a support user and company admin of "Alpha Capital"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Zeta Partners" has a form type "Investor"
    And "Sam" is signed in
    When they open the old clone address for the "Investor" form type of "Zeta Partners"
    Then the request is answered with not found
    And "Alpha Capital" has no "Investor" form type

  # M25-2 — Edge case: a company admin who is not support clones another firm's form type
  @security @rack_test
  Scenario: M25-2 Only support clones another firm's form type
    Given the firm "Alpha Capital" with company admin "Priya"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Zeta Partners" has a form type "Investor"
    And "Priya" is signed in
    When they clone the "Investor" form type of "Zeta Partners"
    Then I am denied access
    And "Alpha Capital" has no "Investor" form type

  # M25-H — Happy path: a support user who is company admin of the destination clones a form type into it
  @security @rack_test
  Scenario: M25-H Support clones a form type into the firm they are admin of
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Sam" is a support user and company admin of "Alpha Capital"
    And the firm "Zeta Partners" with company admin "Omar"
    And "Zeta Partners" has a form type "Investor"
    And "Sam" is signed in
    When they clone the "Investor" form type of "Zeta Partners"
    Then "Alpha Capital" has a "Investor" form type

  # ---- M27 template rendering ----------------------------------------------------------------

  # M27-1 — Edge case: Sablon calls every segment of a merge field, so a GP-uploaded template with «=investor.destroy» would delete the stakeholder while the document is generated
  @security
  Scenario: M27-1 A template field that would delete the stakeholder fails generation and the stakeholder stays
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has the stakeholder "Ravi Iyer" for document generation
    When a template with the merge field "=investor.destroy" is generated for the stakeholder
    Then the generation fails with "readonly mode"
    And the stakeholder "Ravi Iyer" still exists

  # M27-2 — Edge case: a prefixed template helper (to_s_) naming a writer is refused before the writer is called
  @security
  Scenario: M27-2 A to_s_ field naming a writer is refused and the stakeholder is not touched
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has the stakeholder "Ravi Iyer" for document generation
    When a template with the merge field "=investor.to_s_touch" is generated for the stakeholder
    Then the generation fails with "is not a readable template field"
    And the stakeholder "Ravi Iyer" was not updated

  # M27-H — Happy path: plain readers and reader helpers still merge into the generated document
  @security
  Scenario: M27-H A template with plain fields renders the stakeholder's values
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has the stakeholder "Ravi Iyer" for document generation
    When a template with the merge field "=investor.investor_name" is generated for the stakeholder
    Then the generated document reads "Ravi Iyer"
    When a template with the merge field "=investor.to_s_category" is generated for the stakeholder
    Then the generated document reads "LP"

  # ---- M28 child ids -------------------------------------------------------------------------

  # M28-1 — Edge case: documents#update with owner_type / owner_id re-owns a fund document onto another firm's fund
  @security @rack_test
  Scenario: M28-1 A document's owner can't be changed to another firm's fund
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has role "company_admin"
    And my firm has a fund "Alpha Fund" with the document "Side Letter"
    And the firm "Zeta Capital" has a fund "Zeta Fund"
    When I change the owner of the document "Side Letter" to the fund "Zeta Fund"
    Then the document "Side Letter" is still owned by the fund "Alpha Fund"

  # M28-2 — Edge case: an ownerless document is attached to another firm's fund
  @security @rack_test
  Scenario: M28-2 An ownerless document can't be attached to another firm's fund
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has role "company_admin"
    And my firm has the ownerless document "Board Pack"
    And the firm "Zeta Capital" has a fund "Zeta Fund"
    When I change the owner of the document "Board Pack" to the fund "Zeta Fund"
    Then the document "Board Pack" has no owner

  # M28-H — Happy path: an ownerless document is attached to one of the firm's own funds (the 65 nil→owner attaches in prod), without needing update rights on the fund itself
  @security @rack_test
  Scenario: M28-H An ownerless document is attached to my firm's fund
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has role "company_admin"
    And my firm has the ownerless document "Board Pack"
    And my firm has a fund "Alpha Fund"
    When I change the owner of the document "Board Pack" to the fund "Alpha Fund"
    Then the document "Board Pack" is still owned by the fund "Alpha Fund"

  # M28-3 — Edge case: a KYC is created for another firm's investor id
  @security
  Scenario: M28-3 A KYC can't be created for another firm's stakeholder
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the firm "Zeta Capital" has the stakeholder "Zeta LP"
    When a KYC of my firm is saved for the stakeholder "Zeta LP"
    Then the KYC is refused with "Investor must be in this record's firm"

  # M28-4 — Edge case: an existing KYC is moved to another investor (attr_readonly would drop the column but still copy that investor's name)
  @security
  Scenario: M28-4 A KYC can't be moved to another stakeholder
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has the stakeholders "Ravi Iyer" and "Meera Rao"
    And my firm has a KYC for the stakeholder "Ravi Iyer"
    When the KYC is moved to the stakeholder "Meera Rao"
    Then the KYC is refused with "Investor cannot be changed"
    And the KYC still belongs to the stakeholder "Ravi Iyer"

  # M28-H3 — Happy path: a KYC is created for the firm's own stakeholder and edited afterwards
  @security
  Scenario: M28-H3 A KYC is created for my firm's stakeholder and can still be edited
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has the stakeholders "Ravi Iyer" and "Meera Rao"
    And my firm has a KYC for the stakeholder "Ravi Iyer"
    When the KYC's full name is changed to "Ravi K Iyer"
    Then the KYC is saved

  # M28-7 — Edge case: user_id / kyc_data_id are not KYC columns, so the KYC form no longer accepts them (sending them only raised a 500)
  @security
  Scenario: M28-7 The KYC form does not accept user_id or kyc_data_id
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the user has role "company_admin"
    Then the KYC form fields for me do not include "user_id, kyc_data_id"
    And the KYC form fields for me include "investor_id, full_name, PAN"

  # M28-5 — Edge case: a task is assigned to a user of another firm
  @security
  Scenario: M28-5 A task can't be assigned to another firm's user
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And the firm "Zeta Capital" has the user "Zara"
    When a task of my firm is assigned to "Zara"
    Then the task is refused with "Assigned to must be in this record's firm"

  # M28-H4 — Happy path: a task is assigned to a colleague, and a task whose assignee is (legacy) in another firm still saves when the assignee is left alone
  @security
  Scenario: M28-H4 A task is assigned to my colleague, and a legacy cross-firm assignee stays editable
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has the user "Kiran"
    And the firm "Zeta Capital" has the user "Zara"
    When a task of my firm is assigned to "Kiran"
    Then the task is saved
    Given a task of my firm was assigned to "Zara" before the check existed
    When the task's details are changed to "Call the LP back"
    Then the task is saved

  # M28-6 — Edge case: an access right names another firm's investor
  @security
  Scenario: M28-6 An access right can't be granted to another firm's stakeholder
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has a fund "Alpha Fund"
    And the firm "Zeta Capital" has the stakeholder "Zeta LP"
    When the fund "Alpha Fund" is granted to the stakeholder "Zeta LP"
    Then the access right is refused with "Investor must be in this record's firm"

  # M28-H5 — Happy path: a grant to the firm's own stakeholder, and a user grant to another firm's user (advisors, support: 1,730 in prod), still save
  @security
  Scenario: M28-H5 Grants to my stakeholder and to an outside user still save
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    And my firm has a fund "Alpha Fund"
    And my firm has the stakeholders "Ravi Iyer" and "Meera Rao"
    And the firm "Zeta Capital" has the user "Zara"
    When the fund "Alpha Fund" is granted to the stakeholder "Ravi Iyer"
    Then the access right is saved
    When the fund "Alpha Fund" is granted to the user "Zara"
    Then the access right is saved

  # ---- M16 report builder --------------------------------------------------------------------

  # M16-1 — Edge case: an employee with access to one fund ran a commitments report over every fund of the firm
  @security @rack_test
  Scenario: M16-1 A fund-restricted employee's commitments report lists only their fund's commitments
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Ravi" is a plain employee of "Alpha Capital"
    And "Alpha Capital" has a fund "Fund A" with a commitment of the investor "Ajay"
    And "Alpha Capital" has a fund "Fund B" with a commitment of the investor "Bina"
    And "Ravi" has access to the fund "Fund A" only
    When "Ravi" runs a report of "CapitalCommitment" with the column "investor_name"
    Then the report lists "Ajay" under "investor_name"

  # M16-2 — Edge case: a joined relation's count included children outside the user's scope (the Decision: hidden even as aggregates)
  @security @rack_test
  Scenario: M16-2 A fund-restricted employee's stakeholder report counts only their fund's commitments
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Ravi" is a plain employee of "Alpha Capital"
    And "Alpha Capital" has a fund "Fund A" with a commitment of the investor "Ajay"
    And "Alpha Capital" has a fund "Fund B" with a commitment of the investor "Ajay"
    And "Ravi" has access to the fund "Fund A" only
    And "Ravi" may read every stakeholder of the firm
    When "Ravi" runs a report of "Investor" with the column "investor_name" and the count of "capital_commitments"
    Then the report row of "Ajay" counts 1 "capital_commitments"

  # M16-3 — Edge case: root_model was constantized from the template, so a crafted root (User) listed the firm's users
  @security @rack_test
  Scenario: M16-3 A report rooted on a model that is not a report root is refused and a stored one runs nothing
    Given the firm "Alpha Capital" with company admin "Priya"
    Then a report-builder report of "Alpha Capital" on "User" is refused
    And a stored report on "User" returns no rows for "Priya"

  # M16-4 — Edge case: the export job read every row of the entity; it now reads as the report's owner when scheduled and as the requester on demand
  @security @rack_test
  Scenario: M16-4 Scheduled exports read as the report's owner and on-demand exports as the requester
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Ravi" is a plain employee of "Alpha Capital"
    And "Ravi" owns a scheduled report-builder report of "CapitalCommitment"
    When the scheduled export of the report runs
    Then the report rows were read as "Ravi"
    When "Priya" exports the report on demand
    Then the report rows were read as "Priya"

  # M16-H — Happy path: the firm's company admin still sees every fund's commitments, and every child in a count
  @security @rack_test
  Scenario: M16-H The company admin's reports cover every fund of the firm
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has a fund "Fund A" with a commitment of the investor "Ajay"
    And "Alpha Capital" has a fund "Fund B" with a commitment of the investor "Ajay"
    And "Alpha Capital" has a fund "Fund B" with a commitment of the investor "Bina"
    When "Priya" runs a report of "CapitalCommitment" with the column "investor_name"
    Then the report lists "Ajay, Ajay, Bina" under "investor_name"
    When "Priya" runs a report of "Investor" with the column "investor_name" and the count of "capital_commitments"
    Then the report row of "Ajay" counts 2 "capital_commitments"
