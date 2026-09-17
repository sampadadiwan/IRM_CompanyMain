Feature: AI Fix Me for document templates
  As a fund admin
  I want to describe a problem with a Word template and have an AI agent fix it
  So that I get a corrected draft to review without hand-editing the template's XML myself

  # The AI is always stubbed — these scenarios exercise the pipeline (report
  # lifecycle, draft document creation, UI wiring), never a real model call.
  #
  # ```mermaid
  # sequenceDiagram
  #   participant FM as Fund Admin
  #   participant UI as Document page
  #   participant Job as TemplateFixJob
  #   participant A as TemplateFixAgent
  #   participant W as DocxWorkspace
  #   FM->>UI: describe the problem, click Run Fix Me
  #   UI->>Job: enqueue (inline in tests)
  #   Job->>A: call(document, issue_description)
  #   A->>W: tool-calling loop edits the template's XML
  #   A->>W: render preview, rezip
  #   W-->>A: new draft Document (source template untouched)
  #   A-->>UI: SupportAgentReport (ready) + download link
  # ```

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the entity has an LLM provider configured
    And a fund exists for the template fix entity
    And the fund has a commitment template document "KYC Template1.docx"

  Scenario: Running Fix Me produces a downloadable draft, leaving the template untouched
    Given the template fix admin is a company admin
    And the Fix Me AI reports back "Fixed the duplicate numbering in section 5.2 by wrapping the alternate variant in a Sablon conditional."
    When I open the fix me modal and describe the issue "Clause numbers duplicate after 5.2.9"
    Then a template fix agent report should exist with status "ready"
    And a new draft document should exist, distinct from the template
    And I should see "Fixed the duplicate numbering in section 5.2 by wrapping the alternate variant in a Sablon conditional."
    And I should see "Download fixed draft"

  Scenario: The Fix Me button is hidden from a non-admin user
    When I visit the template document page
    Then I should not see "Fix Me"

  # TemplateFixAgent fixes template STRUCTURE only (numbering, indentation,
  # pagination) — nothing in its remaining toolset ever touches a <w:t> text
  # element, so the fixed draft must always have the exact same paragraph
  # count, word count, and words as the original, in order. This is enforced
  # as a hard gate (DocxWorkspace#validate_content_unchanged!) before the
  # draft is even saved. With the AI stubbed (no real tool calls), only the
  # deterministic formatting/numbering fixers run against the real fixture —
  # proving the invariant holds on an actual template with known
  # formatting/numbering bugs, not just a trivial no-op case.
  Scenario: Fixing a real template with formatting bugs preserves every word
    Given the template fix admin is a company admin
    And the fund has a commitment template document "MessedUpDocTemplate.docx"
    And the Fix Me AI reports back "Corrected the clause numbering and indentation round-trip issues."
    When I open the fix me modal and describe the issue "Numbering under section 2 is wrong, and there's a blank page after clause 5.2.9"
    Then a template fix agent report should exist with status "ready"
    And a new draft document should exist, distinct from the template
    And the fix should report a passing content check
