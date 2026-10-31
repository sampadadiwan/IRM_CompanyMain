# Export PowerPoint on an assistant conversation (ppt_export_controller) — a real-browser test, since the
# deck is built in the page's JavaScript. Each answer is placed piece by piece at measured heights, so a
# long answer flows onto continuation slides instead of being drawn on top of itself.
# Worked examples: openspec/changes/ai-chat-kit/design.md#worked-examples
Feature: Export an assistant conversation to PowerPoint

  Background:
    Given "Priya Sharma" is a fund manager at "Golden Angels" with the fund "Golden Angels Fund I"
    And Priya has a Specific Fund Assistant conversation on "Golden Angels Fund I" with a long answer in the layout
    When Priya opens the Specific Fund Assistant for "Golden Angels Fund I"
    And Priya exports the conversation to PowerPoint

  # H31 — Happy path: every slide is titled with the question; Key figures, Verdict, Checks, headings and text all come through
  Scenario: The answer's content is in the deck
    Then every slide is titled "Which LPs are overdue on Call 3?"
    And the deck contains every heading, figure and check of the answer

  # X51 — Error case: a long answer (6 key figures, a long paragraph, a 30-row table) never overlaps — the bug was Key figures drawn under Details
  Scenario: Nothing is drawn on top of anything else
    Then every text box is tall enough for its text
    And no two text boxes or tables overlap on any slide
    And nothing runs off the bottom of a slide

  # E60 — Edge case: a table too long for one slide continues on the next with its header row repeated, and loses no rows
  Scenario: A long table continues across slides
    Then the table's 30 rows are all in the deck, split across slides with the header "LP | Status | Amount" on each part
