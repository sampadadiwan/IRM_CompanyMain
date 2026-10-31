@security
Feature: Investment opportunity widgets never run GP-authored markup in an LP's session (L13)
  CiWidget embed code is accepted only as a single https YouTube /embed/ iframe, and the page always
  rebuilds a sandboxed iframe from the parsed player URL instead of echoing the stored HTML. Widget text
  goes through the sanitizer: formatting stays, script, event handlers and styles go.
  docs/security/security_review_2026_10.md (L13)

  Background:
    Given there is a widget firm "Widget Capital"

  # L13-H1 — Happy path: a YouTube embed is accepted and shown as a sandboxed, lazy player
  Scenario: L13-H1 A YouTube embed is accepted and rebuilt as a sandboxed player
    Then the embed '<iframe width="560" height="315" src="https://www.youtube.com/embed/dQw4w9WgXcQ" allowfullscreen></iframe>' is accepted
    When a widget stored with the embed '<iframe src="https://www.youtube.com/embed/dQw4w9WgXcQ" onload="alert(1)"></iframe>' is shown
    Then the page gets a sandboxed player for "https://www.youtube.com/embed/dQw4w9WgXcQ"
    And the rendered HTML does not contain "onload"

  # L13-X1 — Edge case: a script is refused, and a stored one renders nothing
  Scenario: L13-X1 A script embed is refused and never rendered
    Then the embed "<script>alert(document.cookie)</script>" is refused
    When a widget stored with the embed "<script>alert(document.cookie)</script>" is shown
    Then nothing is rendered for the embed

  # L13-X2 — Edge case: an iframe from another host, over http, or off the /embed/ path is refused
  Scenario: L13-X2 Iframes that are not a YouTube https player are refused
    Then the embed '<iframe src="https://evil.example.com/embed/x"></iframe>' is refused
    And the embed '<iframe src="http://www.youtube.com/embed/dQw4w9WgXcQ"></iframe>' is refused
    And the embed '<iframe src="https://www.youtube.com/watch?v=dQw4w9WgXcQ"></iframe>' is refused
    And the embed '<iframe src="javascript:alert(1)"></iframe>' is refused

  # L13-X5 — Edge case: a player iframe with anything else alongside it is refused
  Scenario: L13-X5 A player iframe with extra markup is refused
    Then the embed '<iframe src="https://www.youtube.com/embed/dQw4w9WgXcQ"></iframe><script>alert(1)</script>' is refused

  # L13-X4 — Edge case: a legacy stored value from another host renders nothing
  Scenario: L13-X4 A stored embed from another host renders nothing
    When a widget stored with the embed '<iframe src="https://evil.example.com/embed/x"></iframe>' is shown
    Then nothing is rendered for the embed

  # L13-X3 — Edge case: script, event handlers and styles are stripped from widget text
  Scenario: L13-X3 Widget text loses script, handlers and styles
    When a widget with the text '<div style="position:fixed" onclick="steal()">Hello<script>alert(1)</script></div><a href="javascript:alert(1)">x</a>' is shown
    Then the rendered HTML does not contain "<script"
    And the rendered HTML does not contain "onclick"
    And the rendered HTML does not contain "style="
    And the rendered HTML does not contain "javascript:"
    And the rendered HTML contains "Hello"

  # L13-H2 — Happy path: the formatting the editor produces is kept
  Scenario: L13-H2 Widget text keeps its formatting
    When a widget with the text '<div><strong>Strategy</strong><ul><li>Seed</li></ul><br><a href="https://example.com">Deck</a></div>' is shown
    Then the rendered HTML contains "<strong>Strategy</strong>"
    And the rendered HTML contains "<li>Seed</li>"
    And the rendered HTML contains 'href="https://example.com"'
