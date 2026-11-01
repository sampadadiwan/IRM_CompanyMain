Feature: LP assistant SQL reads only the LP's own data - 2026-10 security review (H5)
  The LP assistant runs SQL the model writes. Its old checks matched the SQL text and each could be
  missed: a comma join, a parenthesised join, a placeholder inside a comment, no investor filter on
  per-LP tables, PAN on investors, INTO / LOAD_FILE / SLEEP. The data is now scoped instead: every
  allowed table is shadowed by a CTE holding only this LP's rows (LpQueryScope), any other real table
  or database name is refused, and literals and comments are stripped before any check.
  Design and worked examples: docs/security/security_review_2026_10.md#h5--lp-assistant-sql-tool

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
    Given the fund has the LP allocation formulas
    Given the fund "Growth Fund I" holds:
      | company        | instrument    | purchases | cost_cr | fmv_cr |
      | Acme Robotics  | Series B CCPS | 1         | 25.00   | 40.00  |
      | Bluefin Health | Series A CCPS | 1         | 20.00   | 22.00  |
    Given LP "Ravi Menon" has folio "F-012" in "Growth Fund I"
    Given LP "Anita Rao" has folio "A-077" in "Growth Fund I"
    Given folio "F-012" has allocation entries:
      | formula                  | company       | instrument    | amount |
      | Allocated Portfolio Cost | Acme Robotics | Series B CCPS | 2.50   |
    Given the fund "Growth Fund I" LP portfolio view is "allocated" with allocation formula "Allocated Portfolio Cost"

  # H5-1 — Edge case: a commitments query without the investor filter still returns only this LP's folio
  @security
  Scenario: H5-1 Commitments without the investor filter are the LP's own
    When LP "Ravi Menon" runs the assistant query "SELECT cc.folio_id FROM capital_commitments cc WHERE cc.entity_id IN ({ENTITY_ID}) AND cc.fund_id IN ({FUND_IDS})"
    Then the assistant answer should name "F-012"
    And the assistant answer should not name "A-077"

  # H5-2 — Edge case: a comma join to users after an alias is refused
  @security
  Scenario: H5-2 A comma join to users is rejected
    When LP "Ravi Menon" runs the assistant query "SELECT u.email FROM funds f, users u WHERE f.entity_id IN ({ENTITY_ID}) AND f.id IN ({FUND_IDS})"
    Then the query response should include "tables not allowed: users"

  # H5-3 — Edge case: a parenthesised join to users is refused
  @security
  Scenario: H5-3 A parenthesised join to users is rejected
    When LP "Ravi Menon" runs the assistant query "SELECT u.email FROM funds f JOIN (users u) ON u.entity_id = f.entity_id WHERE f.entity_id IN ({ENTITY_ID}) AND f.id IN ({FUND_IDS})"
    Then the query response should include "tables not allowed: users"

  # H5-3a — Edge case: a schema-qualified name, which would bypass the scope CTEs, is refused
  @security
  Scenario: H5-3a A schema-qualified table is rejected
    When LP "Ravi Menon" runs the assistant query "SELECT x.folio_id FROM main.capital_commitments x JOIN funds f ON f.id = x.fund_id WHERE f.entity_id IN ({ENTITY_ID}) AND f.id IN ({FUND_IDS})"
    Then the query response should include "schema not allowed: main"

  # H5-4 — Edge case: PAN is not a column the LP can read, and another LP's investor row is not there at all
  @security
  Scenario: H5-4 Another LP's PAN is never returned
    Given the investor "Anita Rao" has PAN "ANITA1234P"
    When LP "Ravi Menon" runs the assistant query "SELECT i.investor_name, i.pan FROM investors i JOIN funds f ON f.entity_id = i.entity_id WHERE i.entity_id IN ({ENTITY_ID}) AND f.id IN ({FUND_IDS})"
    Then the query response should include "SQL execution failed"
    And the assistant answer should not name "ANITA1234P"
    When LP "Ravi Menon" runs the assistant query "SELECT i.* FROM investors i JOIN funds f ON f.entity_id = i.entity_id WHERE i.entity_id IN ({ENTITY_ID}) AND f.id IN ({FUND_IDS})"
    Then the assistant answer should name "Ravi Menon"
    And the assistant answer should not name "Anita Rao, ANITA1234P"

  # H5-5 — Edge case: file and timing functions and INTO are refused
  @security
  Scenario Outline: H5-5 LOAD_FILE, INTO OUTFILE and SLEEP are rejected
    When LP "Ravi Menon" runs the assistant query "<query>"
    Then the query response should include "<message>"

    Examples:
      | query                                                                                                                  | message                     |
      | SELECT LOAD_FILE('/etc/passwd') AS f FROM funds f WHERE f.entity_id IN ({ENTITY_ID}) AND f.id IN ({FUND_IDS})          | forbidden keyword: LOAD_FILE |
      | SELECT f.name FROM funds f WHERE f.entity_id IN ({ENTITY_ID}) AND f.id IN ({FUND_IDS}) INTO OUTFILE '/tmp/lp.csv'      | forbidden keyword: INTO     |
      | SELECT SLEEP(10) AS s FROM funds f WHERE f.entity_id IN ({ENTITY_ID}) AND f.id IN ({FUND_IDS})                         | forbidden keyword: SLEEP    |

  # H5-5a — Edge case: placeholders inside a comment do not count as scope
  @security
  Scenario: H5-5a A placeholder only in a comment is rejected
    When LP "Ravi Menon" runs the assistant query "SELECT f.name FROM funds f WHERE f.id > 0 -- {ENTITY_ID} {FUND_IDS}"
    Then the query response should include "missing {ENTITY_ID} placeholder"

  # H5-H — Happy path (drift guard, like mcp_ontology.feature): every skill's first example query runs as documented
  @security
  Scenario: H5-H Every skill's first example query executes
    When LP "Ravi Menon" runs the first example query of every LP assistant skill
    Then every skill's first example query executes

  # H5-X — Edge case: a hidden holding stays absent even when the visible-holdings filter is neutralised with OR
  @security
  Scenario Outline: H5-X A hidden holding is absent whatever the filter says
    When LP "Ravi Menon" runs the assistant query "<query>"
    Then the assistant answer should name "Acme Robotics"
    And the assistant answer should not name "Bluefin Health"

    Examples:
      | query                                                                                                                                                                            |
      | SELECT api.portfolio_company_name FROM aggregate_portfolio_investments api WHERE api.entity_id IN ({ENTITY_ID}) AND api.fund_id IN ({FUND_IDS}) AND (api.id IN ({VISIBLE_API_IDS}) OR 1=1) |
      | SELECT pi.portfolio_company_name FROM portfolio_investments pi WHERE pi.entity_id IN ({ENTITY_ID}) AND pi.fund_id IN ({FUND_IDS}) AND (pi.id IN ({VISIBLE_PI_IDS}) OR 1=1)        |

  # H5-X — Error case: a holdings query without the visible-holdings placeholder is rejected
  @security
  Scenario: H5-X A holdings query without the visible-holdings placeholder is rejected
    When LP "Ravi Menon" runs the assistant query "SELECT api.portfolio_company_name FROM aggregate_portfolio_investments api WHERE api.entity_id IN ({ENTITY_ID}) AND api.fund_id IN ({FUND_IDS})"
    Then the query response should include "missing {VISIBLE_API_IDS} placeholder"
