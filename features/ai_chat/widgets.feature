# AI chat kit, phase 8 — optional answer widgets. The assistant adds Verdict, Checks or What to do only
# when the question calls for one (a catalogue with triggers and examples, AiChatAnswerLayout::WIDGETS);
# the renderer draws a well-formed one and leaves a malformed one as plain text. Status badges need no
# choice: the renderer adds them to a table's Status column.
# Worked examples: openspec/changes/ai-chat-kit/design.md#worked-examples
Feature: Optional answer widgets

  # H23 — Happy path: a Verdict becomes a coloured banner by its opening word
  Scenario Outline: Verdict banner
    Given an answer:
      """
      ## Summary
      Checked.

      ## Verdict
      <verdict> — <reason>
      """
    When it is rendered in strict mode
    Then the answer shows a "<colour>" verdict banner reading "<label>" and "<reason>"

    Examples:
      | verdict    | reason                                  | colour    | label      |
      | Mismatch   | the remittance exceeds the call by ₹50,000 | danger    | Mismatch   |
      | Matches    | the remittances add up to the call      | success   | Matches    |
      | Can't tell | the bank statement is not uploaded      | secondary | Can't tell |

  # E51 — Edge case: a Verdict without one of the three words stays plain text
  Scenario: Malformed verdict
    Given an answer:
      """
      ## Verdict
      Probably fine, but check the statement.
      """
    When it is rendered in strict mode
    Then the answer shows no verdict banner
    And the rendered answer says "Probably fine, but check the statement."

  # H24 — Happy path: Checks list failed checks first, with their marks as icons
  Scenario: Checks
    Given an answer:
      """
      ## Checks
      - ✓ Remittances add up to ₹5,50,000
      - ✗ Call 2 asked for ₹5,00,000
      """
    When it is rendered in strict mode
    Then the checks read, in order:
      | fail | Call 2 asked for ₹5,00,000         |
      | pass | Remittances add up to ₹5,50,000    |

  # E52 — Edge case: Checks without ✓ or ✗ stay a plain list
  Scenario: Unmarked checks
    Given an answer:
      """
      ## Checks
      - Remittances add up
      """
    When it is rendered in strict mode
    Then the answer shows no checks card

  # H25 — Happy path: What to do becomes numbered steps in a card
  Scenario: What to do
    Given an answer:
      """
      ## What to do
      1. Open Capital Calls › Call 2 › Edit
      2. Record the ₹50,000 as an advance
      """
    When it is rendered in strict mode
    Then the steps read "Open Capital Calls › Call 2 › Edit" and "Record the ₹50,000 as an advance"

  # H26 — Happy path: known status words in a Status column become badges; other words and columns are untouched
  Scenario: Status badges
    Given an answer:
      """
      | Remittance | Status         | Note    |
      |---|---|---|
      | 13573      | Pending        | Paid    |
      | 13574      | Overpaid       | -       |
      | 13575      | Paid, verified | -       |
      | 13576      | On hold        | -       |
      """
    When it is rendered in rich mode
    Then the status badges read:
      | Pending        | warning |
      | Overpaid       | danger  |
      | Paid, verified | success |
    And "On hold" and the Note column are not badges

  # E53 — Edge case: the prompt offers widgets as an optional catalogue with examples, including an answer with none
  Scenario: Widgets are optional in the prompt
    When the answer layout instructions are read
    Then they say "Most answers need none; rarely use more than two. Never add one to fill space."
    And they give the example "→ Summary only (no Verdict, no Checks)"

  # E54 — Edge case: each answer's sections are logged, so a widget used too often shows up
  Scenario: Widget usage is logged
    Given an answer:
      """
      ## Summary
      x

      ## Verdict
      Matches — y

      **Checks**
      - ✓ z
      """
    Then the answer's sections are "summary, verdict, checks"
    And logging it for "assistants" writes "[ai_chat] answer sections source=assistants sections=summary,verdict,checks"
