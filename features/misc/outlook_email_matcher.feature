@notification
Feature: Mail add-in matching and filing
  As a fund manager
  I want to match emails to investors and file them from Outlook or Gmail
  So that investor correspondence is recorded in CapHive

  Background:
    Given a fund exists
    And an investor exists in that fund
    And an approved investor access exists for "john@example.com" for that investor

  # ---------------------------------------------------------------- matching

  Scenario: Matching a single investor by from_email
    When I match an email from "john@example.com"
    Then the match result should be "single"
    And the matched investor should be that investor

  Scenario: No match found
    When I match an email from "unknown@example.org"
    Then the match result should be "none"

  # Matching is sender-only by design. A recipient address says little about who an email
  # is about — everyone on a thread is a recipient — so a CC'd investor is NOT suggested.
  # Such an email is filed by picking the record by hand.
  #
  # Driven through the API because the matcher has no to_emails/cc_emails parameters at
  # all now; the clients still send them (they are stored on the filed record), so what is
  # worth asserting is that the endpoint accepts them and they change nothing.
  Scenario: An investor in CC is not matched
    Given another investor exists in that fund
    And that other investor has primary_email "contact@jane.com"
    And I have a mail add-in token
    When I call the mail API match endpoint for "external@example.org" with cc "contact@jane.com"
    Then the mail API response status should be 200
    And the mail API match type should be "none"

  # Outbound mail: the fund manager is the sender and the investor only appears in To.
  # Deliberately unmatched — the user selects the record instead.
  Scenario: An investor addressed in To on outbound mail is not matched
    Given I have a mail add-in token
    When I call the mail API match endpoint for "manager@fund.com" with to "john@example.com"
    Then the mail API response status should be 200
    And the mail API match type should be "none"

  # An advisor or family-office contact can hold approved access to several records. The
  # sender is unambiguous but the target is not, so every record they act for is offered
  # and the user picks — never a silent guess at one of them.
  Scenario: A sender with access to several investors returns all of them
    Given another investor exists in that fund
    And an approved investor access exists for "john@example.com" for that other investor
    When I match an email from "john@example.com"
    Then the match result should be "multiple"
    And the matched investor should be that investor
    And the matched investor should be that other investor

  # Found on the first real mailbox test: an investor was registered against the tester's
  # own Gmail address. The matcher dropped only user.email (the CapHive login), which is a
  # different string from the mail account, so the user's own address still matched.
  Scenario: An investor registered against the user's own mailbox address is not matched
    Given another investor exists in that fund
    And that other investor has primary_email "me@personal.example"
    When I match an email from "me@personal.example" read from mailbox "me@personal.example"
    Then the match result should be "none"

  # The same address must still match when somebody else's mailbox is being read.
  Scenario: That address still matches when it is not the reader's own
    Given another investor exists in that fund
    And that other investor has primary_email "me@personal.example"
    When I match an email from "me@personal.example" read from mailbox "someone.else@fund.com"
    Then the match result should be "single"
    And the matched investor should be that other investor

  # A shared generic mail host says nothing about who the counterparty is.
  Scenario: Generic sender domains do not match on domain alone
    Given another investor exists in that fund
    And that other investor has primary_email "someone@gmail.com"
    When I match an email from "different-person@gmail.com"
    Then the match result should be "none"

  # ---------------------------------------------------------------- API

  Scenario: API rejects a request with no bearer token
    When I call the mail API match endpoint without a token
    Then the mail API response status should be 401

  Scenario: API rejects a request with an invalid bearer token
    Given I have an invalid mail add-in token
    When I call the mail API match endpoint for "john@example.com"
    Then the mail API response status should be 401

  Scenario: API returns the matched investor and why it matched
    Given I have a mail add-in token
    When I call the mail API match endpoint for "john@example.com"
    Then the mail API response status should be 200
    And the mail API match type should be "single"
    And the mail API candidates should include that investor
    And the mail API candidate reason should be "contact"

  Scenario: API files an email against the investor
    Given I have a mail add-in token
    When I file an email with subject "Capital call question" and message id "<abc-1@example.com>"
    Then the mail API response status should be 201
    And an incoming email should be created for that investor with subject "Capital call question"
    And the filed email should record who filed it

  # Double click, network retry, or a second colleague filing the same thread.
  Scenario: Re-filing the same email does not create a duplicate
    Given I have a mail add-in token
    And I file an email with subject "Capital call question" and message id "<abc-2@example.com>"
    When I file an email with subject "Capital call question" and message id "<abc-2@example.com>"
    Then the mail API response status should be 200
    And the mail API response should report the email was already filed
    And only 1 incoming email should exist with message id "<abc-2@example.com>"

  Scenario: Matching reports an email that has already been filed
    Given I have a mail add-in token
    And I file an email with subject "Already here" and message id "<abc-3@example.com>"
    When I call the mail API match endpoint for "john@example.com" with message id "<abc-3@example.com>"
    Then the mail API response should say the email is already filed
    And the already filed response should name that investor

  Scenario: Undoing a filing removes it
    Given I have a mail add-in token
    And I file an email with subject "Filed by mistake" and message id "<abc-4@example.com>"
    When I undo that filing
    Then the mail API response status should be 200
    And no incoming email should exist with message id "<abc-4@example.com>"

  # Emails from one sender to one investor share a document folder, and that folder
  # cascades to every document inside it.
  Scenario: Undoing a filing leaves other emails' documents intact
    Given I have a mail add-in token
    And I file an email with subject "First" and message id "<share-1@example.com>"
    And that filing has an attached document
    And I file an email with subject "Second" and message id "<share-2@example.com>"
    And that filing shares the first filing's document folder
    When I undo that filing
    Then the mail API response status should be 200
    And the first filing should still have its document

  # Two emails with no Message-ID must not collide in the unique dedup index.
  Scenario: Filing two emails without a message id does not report a false duplicate
    Given I have a mail add-in token
    And I file an email with subject "No id one" and no message id
    When I file an email with subject "No id two" and no message id
    Then the mail API response status should be 201
    And the mail API response should not report the email was already filed
    And an incoming email should be created for that investor with subject "No id two"

  Scenario: A token issued for another OAuth client is rejected
    Given I have a token issued to a different OAuth application
    When I call the mail API match endpoint for "john@example.com"
    Then the mail API response status should be 403

  # The old endpoint returned every investor in the entity with no search or limit.
  Scenario: Owner search is scoped to the query
    Given I have a mail add-in token
    And another investor exists in that fund
    And that other investor is named "Zephyr Capital"
    When I search the mail API owners endpoint for "Zephyr"
    Then the mail API owners response should include "Zephyr Capital"
    And the mail API owners response should not include that investor

  # Filing records correspondence rather than mutating the investor, so it must not
  # require :investor_update — that locked out read-only IR and compliance staff.
  Scenario: Filing is gated on view permission, not update permission
    Then filing should be gated on view permission and not on update permission
