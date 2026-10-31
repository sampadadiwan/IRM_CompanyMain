# AI Slides — an assistant chat's deck (SlideGeneratorService + assistants/presentation_templates).
# The model writes a JSON blueprint; these scenarios draw blueprints directly (no AI call).
# Worked examples: openspec/changes/ai-chat-kit/design.md#worked-examples
@rack_test
Feature: AI Slides deck

  # H27 — Happy path: every slide type draws, numbered, each content slide explaining itself, with no filler text
  Scenario: A full deck
    Given a slide blueprint with one slide of each type
    When the blueprint is drawn for "AX" on "31/10/2026"
    Then the deck has 7 slides of types "title, key_figures, chart, insights, table, comparison, next_steps"
    And the slides are numbered "1 / 7" to "7 / 7"
    And every slide but the title says what it means
    And the deck has none of the old filler text
    And the footer reads "AX · 31/10/2026"

  # E55 — Edge case: a slide without content is left out, and the numbering counts only drawn slides
  Scenario: Empty slides are skipped
    Given a slide blueprint with an insights slide that has no items and a key figures slide
    When the blueprint is drawn for "AX" on "31/10/2026"
    Then the deck has 1 slides of types "key_figures"
    And the slides are numbered "1 / 1" to "1 / 1"

  # E56 — Edge case: an unknown icon or tone falls back, so no icon box is ever empty
  Scenario: Unknown icons and tones fall back
    Given a slide blueprint with an insights slide using the icon "made-up" and tone "weird"
    When the blueprint is drawn for "AX" on "31/10/2026"
    Then the slide's icon is "bulb" and its card's tone is "neutral"

  # E57 — Edge case: decks saved before the redesign (hero, bullets, split_chart) draw with the new templates
  Scenario: Old slide types
    Given an old-style slide blueprint with hero, bullets and split_chart slides
    When the blueprint is drawn for "AX" on "31/10/2026"
    Then the deck has 3 slides of types "title, insights, chart"
    And the chart slide says what it means from its old analysis

  # E58 — Edge case: the brief asks for grounded numbers, currency amounts, a takeaway per slide and known icons
  Scenario: The slide brief
    When the slide brief is read
    Then it says "Use only facts and numbers that appear in the conversation"
    And it says "Never show a raw _cents value"
    And it says "Every slide except \"title\" has a \"takeaway\""
    And it lists the icon "report-money"

  # X48 — Error case: drawing a blueprint does not change it, so the saved blueprint keeps its slide types
  Scenario: The blueprint is saved intact
    Given a slide blueprint with one slide of each type
    When the blueprint is drawn for "AX" on "31/10/2026"
    Then every slide in the blueprint still names its template

  # H28 — Happy path: a saved deck can be regenerated from the AI Slides page
  Scenario: Regenerate
    Given "Priya Sharma" is a fund manager at "Golden Angels" with the fund "Golden Angels Fund I"
    And Priya has a Specific Fund Assistant chat on "Golden Angels Fund I" with saved slides "Q3 overdue LPs"
    When Priya opens that chat's AI Slides
    Then the page offers Regenerate for that chat

  # X49 — Error case: a malformed blueprint (a slide that is not an object, bad chart options, datasets or data) draws what it can and never fails
  Scenario: Malformed blueprint
    Given a slide blueprint with a stray string, a chart with bad options and datasets, and a key figures slide
    When the blueprint is drawn for "AX" on "31/10/2026"
    Then the deck has 2 slides of types "chart, key_figures"

  # E59 — Edge case: decks saved before the redesign have no "template" key (the old renderer deleted it); the type is read from the fields
  Scenario: Saved slides without their type
    Given a saved old-style blueprint with no template keys: a title, bullets, a chart and a comparison
    When the blueprint is drawn for "AX" on "31/10/2026"
    Then the deck has 4 slides of types "title, insights, chart, comparison"

  # H29 — Happy path: opening a saved deck redraws its blueprint with the current templates, with no AI call
  Scenario: A saved deck is redrawn
    Given "Priya Sharma" is a fund manager at "Golden Angels" with the fund "Golden Angels Fund I"
    And Priya has a Specific Fund Assistant chat on "Golden Angels Fund I" with saved slides "Q3 overdue LPs"
    When the chat's slides are generated without forcing
    Then the slides are drawn from the saved blueprint with the current templates

  # X50 — Error case: AI Slides for a colleague's chat is refused (a deck shows the chat's transcript), and no deck is made
  Scenario: A colleague's chat
    Given "Priya Sharma" is a fund manager at "Golden Angels" with the fund "Golden Angels Fund I"
    And Priya's colleague "Meera Nair" has a Specific Fund Assistant chat on "Golden Angels Fund I" asking "Colleague question"
    When Priya opens AI Slides for that colleague's chat
    Then the slides page is not found and no deck is queued
