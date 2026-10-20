# Support Console — Claude's SQL stays inside one client: joins only along real links, the deny list,
# hidden scope columns and the row check. The SQL rules are proven by the machine's node tests
# (support_console/machine/test/tenant_scope.test.js), run here by ID.
# Worked examples: openspec/changes/support-console-tenant-scope/design.md#worked-examples
@rack_test @support_console @sync-http
Feature: Support Console tenant scope

  # H1 — Happy path: a real-link join runs and its hidden column is stripped
  Scenario: A real-link join runs and its hidden column is stripped
    When the support machine tests matching "tenant-scope H1 —" run
    Then they pass

  # H2 — Happy path: investor → attachments → file names runs
  Scenario: Investor → attachments → file names runs
    When the support machine tests matching "tenant-scope H2 —" run
    Then they pass

  # H3 — Happy path: a note joined with its record type runs
  Scenario: A note joined with its record type runs
    When the support machine tests matching "tenant-scope H3 —" run
    Then they pass

  # H4 — Happy path: an investor and its LP firm are shown, never held back
  Scenario: An investor and its LP firm are shown, never held back
    When the support machine tests matching "tenant-scope H4 —" run
    Then they pass

  # H5 — Happy path: grouped totals carry MIN/MAX scope columns
  Scenario: Grouped totals carry MIN/MAX scope columns
    When the support machine tests matching "tenant-scope H5 —" run
    Then they pass

  # H6 — Happy path: an everyday lookup comes back exactly as asked
  Scenario: An everyday lookup comes back exactly as asked
    When the support machine tests matching "tenant-scope H6 —" run
    Then they pass

  # H7 — Happy path: the link list is built from the schema on every publish
  Scenario: Link list published
    When the link list is built from the app's schema
    Then the link list joins "doc_shares.document_id" to "documents"
    And the link list joins "action_text_rich_texts.record_id" by its type "record_type"
    And the link list names the class of "investors" as "Investor"

  # E1 — Edge case: a link written the other way round runs
  Scenario: A link written the other way round runs
    When the support machine tests matching "tenant-scope E1 —" run
    Then they pass

  # E2 — Edge case: IN returning the right column runs
  Scenario: IN returning the right column runs
    When the support machine tests matching "tenant-scope E2 —" run
    Then they pass

  # E3 — Edge case: commitments totalled per LP firm run
  Scenario: Commitments totalled per LP firm run
    When the support machine tests matching "tenant-scope E3 —" run
    Then they pass

  # E4 — Edge case: UNION arms share positional scope columns, so rows still merge
  Scenario: UNION arms share positional scope columns, so rows still merge
    When the support machine tests matching "tenant-scope E4 —" run
    Then they pass

  # E5 — Edge case: DISTINCT keeps its rows
  Scenario: DISTINCT keeps its rows
    When the support machine tests matching "tenant-scope E5 —" run
    Then they pass

  # E6 — Edge case: a table added by a migration is readable along its link after the next publish, refused before
  Scenario: New table after a migration
    When the link list is built from a schema where "doc_comments.document_id" has a foreign key to "documents"
    Then the link list joins "doc_comments.document_id" to "documents"
    When the support machine tests matching "tenant-scope E6 —" run
    Then they pass

  # E7 — Edge case: a linked table used without its link is refused, naming the link
  Scenario: A linked table used without its link is refused, naming the link
    When the support machine tests matching "tenant-scope E7 —" run
    Then they pass

  # E8 — Edge case: a polymorphic type naming the wrong class is refused
  Scenario: A polymorphic type naming the wrong class is refused
    When the support machine tests matching "tenant-scope E8 —" run
    Then they pass

  # E9 — Edge case: a column Claude names entity_id is neither refused nor held back
  Scenario: A column Claude names entity_id is neither refused nor held back
    When the support machine tests matching "tenant-scope E9 —" run
    Then they pass

  # E10 — Edge case: tags through the investor's taggings run
  Scenario: Tags through the investor's taggings run
    When the support machine tests matching "tenant-scope E10 —" run
    Then they pass

  # E11 — Edge case: an LP firm reached through another *_entity_id column runs
  Scenario: An LP firm reached through another *_entity_id column runs
    When the support machine tests matching "tenant-scope E11 —" run
    Then they pass

  # E12 — Edge case: a LEFT JOIN miss returns the document
  Scenario: A LEFT JOIN miss returns the document
    When the support machine tests matching "tenant-scope E12 —" run
    Then they pass

  # E13 — Edge case: an aggregate over no rows is not held back
  Scenario: An aggregate over no rows is not held back
    When the support machine tests matching "tenant-scope E13 —" run
    Then they pass

  # E14 — Edge case: LIMIT and ORDER BY are unchanged
  Scenario: LIMIT and ORDER BY are unchanged
    When the support machine tests matching "tenant-scope E14 —" run
    Then they pass

  # X1 — Error case: a wrong-column join is refused before it runs, naming the link
  Scenario: A wrong-column join is refused before it runs, naming the link
    When the support machine tests matching "tenant-scope X1 —" run
    Then they pass

  # X2 — Error case: IN returning the wrong column is refused
  Scenario: IN returning the wrong column is refused
    When the support machine tests matching "tenant-scope X2 —" run
    Then they pass

  # X3 — Error case: a polymorphic join without its type is refused
  Scenario: A polymorphic join without its type is refused
    When the support machine tests matching "tenant-scope X3 —" run
    Then they pass

  # X4 — Error case: a table with no link to client data is not allowed
  Scenario: A table with no link to client data is not allowed
    When the support machine tests matching "tenant-scope X4 —" run
    Then they pass

  # X5 — Error case: AI chat logs are not allowed, though their links are real
  Scenario: AI chat logs are not allowed, though their links are real
    When the support machine tests matching "tenant-scope X5 —" run
    Then they pass

  # X6 — Error case: the LP firm's own funds are refused
  Scenario: The LP firm's own funds are refused
    When the support machine tests matching "tenant-scope X6 —" run
    Then they pass

  # X7 — Error case: a lookup held back for another client's rows is recorded as blocked and flagged, and super users are alerted
  Scenario: Held-back lookup recorded and alerted
    Given the client "Golden Angels" has support access "on"
    And "Meera" is a support user
    And "Priya" is a super user without the support role
    And "Meera" is mapped to "Golden Angels" until "2099-12-31"
    And I am logged in as "Meera"
    And the relay answers "Answered from the other lookups" after these lookups:
      | sql                                                                                                   | outcome | reason                   | row_count | flagged |
      | SELECT d.name, s.email FROM documents d JOIN doc_shares s ON s.document_id = d.id WHERE d.entity_id = 18 | blocked | rows from another client | 2         | yes     |
    When I open the Support Console for "Golden Angels"
    And I ask "Who were the Q3 reports shared with?"
    Then a support console query is recorded as "blocked" because "rows from another client"
    And the support console query is flagged
    And the super user "Priya" has 1 flagged-lookup alert
    And I see the answer "Answered from the other lookups"

  # X8 — Error case: without the link list no table lacking entity_id can be read
  Scenario: Without the link list no table lacking entity_id can be read
    When the support machine tests matching "tenant-scope X8 —" run
    Then they pass

  # X9 — Error case: the __scope_ prefix is reserved
  Scenario: The __scope_ prefix is reserved
    When the support machine tests matching "tenant-scope X9 —" run
    Then they pass

  # X10 — Error case: a shape the hidden columns cannot extend is refused
  Scenario: A shape the hidden columns cannot extend is refused
    When the support machine tests matching "tenant-scope X10 —" run
    Then they pass

  # X11 — Error case: a row from another client holds back the whole result
  Scenario: A row from another client holds back the whole result
    When the support machine tests matching "tenant-scope X11 —" run
    Then they pass
