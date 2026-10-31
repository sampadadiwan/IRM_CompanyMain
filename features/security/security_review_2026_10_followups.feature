# Security review 2026-10 — follow-ups (F) found after the approved fixes landed.
#   F1 — the Customer Support Agent's SQL tool (FmRunQueryTool) had its own checks and kept the bypasses H5
#        closed for the LP tool: it now shares H5's statement checks and reads every allowed table through
#        FmQueryScope CTEs holding only the fund manager's own entity rows.
#   F2 — the tasks list heading and the kanban card's source link named records looked up by a bare id in any
#        firm: they now name a record only when its own policy lets the user open it.
#   F3 — the investment solutions layout echoed CiProfile details as raw HTML: it now goes through the L13
#        sanitizer (CiWidgetHelper#ci_widget_rich_text).
#   F4 — GenerateSectionContentJob found the report's agent in the analyst's firm: it now uses the portfolio
#        company's firm (the C3 tenancy rule).
#   F5 — pre-existing bugs found during the review: interests#allocate / allocations#verify had no policy
#        predicate (now firm-only), boards got their columns twice, dead routes, the LP assistant skills'
#        'PortfolioCompany' owner_type, the LIMIT a trailing comment swallowed, the sample workbook's
#        custom_fields.send and the unrouted /oauth/introspect throttle.
# Design: docs/security/security_review_2026_10.md (cards H5, L13, L14, C3)
@security
Feature: Security review 2026-10 follow-ups

  # ---- F1 Customer Support Agent SQL tool ----------------------------------------------------

  Rule: F1 — the fund manager's SQL reads only its own entity, through the same checks as the LP tool

    Background:
      Given these fund manager firms for the support SQL tool:
        | firm          | fund         | investor   | pan        | kyc name        |
        | Artha Capital | Artha Fund I | Ravi Menon | RAVIM1234P | Ravi Menon KYC  |
        | Zeta Capital  | Zeta Fund I  | Zoya Khan  | ZOYAK1234P | Zoya Khan KYC   |

    # F1-1 — Edge case: a neutralised or missing entity filter (OR 1=1, comma join, subquery) still returns only the fund manager's own rows
    Scenario Outline: F1-1 A neutralised entity filter still reads only the fund manager's own rows
      When the support agent of "Artha Capital" runs the query "<query>"
      Then the assistant answer should name "<own>"
      And the assistant answer should not name "<other>"

      Examples:
        | query                                                                                                   | own            | other                 |
        | SELECT f.name FROM funds f WHERE f.entity_id IN ({ENTITY_ID}) OR 1=1                                    | Artha Fund I   | Zeta Fund I           |
        | SELECT i.investor_name, i.pan FROM funds f, investors i WHERE f.entity_id IN ({ENTITY_ID})              | Ravi Menon     | Zoya Khan, ZOYAK1234P |
        | SELECT k.full_name FROM investor_kycs k WHERE k.entity_id IN ({ENTITY_ID}) OR k.id > 0                  | Ravi Menon KYC | Zoya Khan KYC         |
        | SELECT f.name FROM funds f WHERE f.id IN (SELECT x.id FROM funds x) AND {ENTITY_ID} > 0                 | Artha Fund I   | Zeta Fund I           |

    # F1-2 — Edge case: a comma join to users after an alias is refused
    Scenario: F1-2 A comma join to users is rejected
      When the support agent of "Artha Capital" runs the query "SELECT u.email FROM funds f, users u WHERE f.entity_id IN ({ENTITY_ID})"
      Then the query response should include "tables not allowed: users"

    # F1-3 — Edge case: a parenthesised join to users, a schema-qualified table and a system schema are refused
    Scenario Outline: F1-3 Parenthesised joins and schema names are rejected
      When the support agent of "Artha Capital" runs the query "<query>"
      Then the query response should include "<message>"

      Examples:
        | query                                                                                                   | message                               |
        | SELECT u.email FROM funds f JOIN (users u) ON u.entity_id = f.entity_id WHERE f.entity_id IN ({ENTITY_ID}) | tables not allowed: users          |
        | SELECT x.name FROM main.funds x WHERE x.entity_id > 0 OR x.entity_id IN ({ENTITY_ID})                   | schema not allowed: main              |
        | SELECT t.table_name FROM information_schema.tables t WHERE 1 IN ({ENTITY_ID})                           | schema not allowed: information_schema |

    # F1-4 — Edge case: WITH, INTO, file / timing / lock functions and @ variables are refused
    Scenario Outline: F1-4 WITH, INTO, LOAD_FILE, SLEEP, BENCHMARK, GET_LOCK and @ are rejected
      When the support agent of "Artha Capital" runs the query "<query>"
      Then the query response should include "<message>"

      Examples:
        | query                                                                                                     | message                       |
        | SELECT LOAD_FILE('/etc/passwd') AS f FROM funds f WHERE f.entity_id IN ({ENTITY_ID})                      | forbidden keyword: LOAD_FILE  |
        | SELECT f.name FROM funds f WHERE f.entity_id IN ({ENTITY_ID}) INTO OUTFILE '/tmp/fm.csv'                  | forbidden keyword: INTO       |
        | SELECT SLEEP(10) AS s FROM funds f WHERE f.entity_id IN ({ENTITY_ID})                                     | forbidden keyword: SLEEP      |
        | SELECT BENCHMARK(1000000, MD5('a')) AS b FROM funds f WHERE f.entity_id IN ({ENTITY_ID})                  | forbidden keyword: BENCHMARK  |
        | SELECT GET_LOCK('fm', 10) AS l FROM funds f WHERE f.entity_id IN ({ENTITY_ID})                            | forbidden keyword: GET_LOCK   |
        | SELECT f.name FROM funds f WHERE f.entity_id IN ({ENTITY_ID}) AND f.id IN (WITH x AS (SELECT 1 AS id) SELECT x.id FROM x) | forbidden keyword: WITH |
        | SELECT @@version AS v FROM funds f WHERE f.entity_id IN ({ENTITY_ID})                                     | variables (@) are not allowed |

    # F1-5 — Edge case: a placeholder only inside a comment or a string literal does not count as scope
    Scenario Outline: F1-5 A placeholder only in a comment or a literal is rejected
      When the support agent of "Artha Capital" runs the query "<query>"
      Then the query response should include "missing {ENTITY_ID} placeholder"

      Examples:
        | query                                                        |
        | SELECT f.name FROM funds f WHERE f.id > 0 -- {ENTITY_ID}     |
        | SELECT '{ENTITY_ID}' AS scope, f.name FROM funds f           |
        | SELECT f.name FROM funds f /* {ENTITY_ID} */ WHERE f.id > 0  |

    # F1-6 — Edge case: a bare column that shares a table's name (notes) is refused with the alias.column hint the model can act on
    Scenario: F1-6 A bare column named like a table is rejected with a hint
      When the support agent of "Artha Capital" runs the query "SELECT name, notes FROM capital_calls WHERE entity_id IN ({ENTITY_ID})"
      Then the query response should include "tables not allowed: notes — if you meant a column of that name, write it as alias.column"

    # F1-H — Happy path (drift guard): the system prompt's example query returns the fund manager's own funds
    Scenario: F1-H The system prompt's example query returns the fund manager's funds
      When the support agent of "Artha Capital" runs the example query of its system prompt
      Then the assistant answer should name "Artha Fund I"
      And the assistant answer should not name "Zeta Fund I"

    # F1-H — Happy path: entity-scoped queries over the allowed tables, with and without {FUND_IDS}, execute
    Scenario Outline: F1-H Entity-scoped queries over the allowed tables execute
      When the support agent of "Artha Capital" runs the query "<query>"
      Then the support query executes

      Examples:
        | query                                                                                                                         |
        | SELECT COUNT(*) AS funds FROM funds WHERE entity_id IN ({ENTITY_ID}) AND deleted_at IS NULL                                   |
        | SELECT i.investor_name, i.category FROM investors i WHERE i.entity_id IN ({ENTITY_ID}) ORDER BY i.investor_name               |
        | SELECT cc.folio_id, cc.committed_amount_cents FROM capital_commitments cc JOIN funds f ON f.id = cc.fund_id WHERE cc.entity_id IN ({ENTITY_ID}) AND cc.fund_id IN ({FUND_IDS}) |
        | SELECT c.name, c.notes FROM capital_calls c WHERE c.entity_id IN ({ENTITY_ID})                                                |
        | SELECT k.full_name, k.verified FROM investor_kycs k WHERE k.entity_id IN ({ENTITY_ID})                                        |
        | SELECT a.email, a.approved FROM investor_accesses a WHERE a.entity_id IN ({ENTITY_ID})                                        |
        | SELECT n.subject, n.email_sent FROM noticed_notifications n WHERE n.entity_id IN ({ENTITY_ID}) ORDER BY n.created_at DESC     |
        | SELECT d.name, fo.full_path FROM documents d LEFT JOIN folders fo ON fo.id = d.folder_id WHERE d.entity_id IN ({ENTITY_ID})   |

  # ---- F2 Name leaks -------------------------------------------------------------------------

  # F2-1 — Edge case: the tasks list heading looked its owner (stakeholder or deal) up by id in any firm, so a company admin saw another firm's name
  @rack_test
  Scenario Outline: F2-1 The tasks list heading does not name another firm's <record>
    Given the firm "Alpha Capital" with company admin "Priya"
    And the firm "Zeta Capital" with company admin "Zed"
    And "Zeta Capital" has an investor "Zeta Secret Stakeholder"
    And "Zeta Capital" has a deal "Zeta Secret Deal"
    And "Priya" is signed in
    When they open the tasks list for the <record> "<name>"
    Then the response does not mention "<name>"

    Examples:
      | record   | name                    |
      | investor | Zeta Secret Stakeholder |
      | deal     | Zeta Secret Deal        |

  # F2-H — Happy path: the firm's own stakeholder and deal still head their tasks lists
  @rack_test
  Scenario Outline: F2-H The firm's own <record> still heads its tasks list
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has an investor "Ajay Family Trust"
    And "Alpha Capital" has a deal "Alpha Growth Deal"
    And "Priya" is signed in
    When they open the tasks list for the <record> "<name>"
    Then the page loads
    And the response mentions "<name>"

    Examples:
      | record   | name              |
      | investor | Ajay Family Trust |
      | deal     | Alpha Growth Deal |

  # F2-2 — Edge case: a kanban card whose data source id points at another firm's deal investor no longer links (names) it, on the card page or its off-canvas panel
  @rack_test
  Scenario: F2-2 A kanban card does not name another firm's deal investor
    Given the firm "Alpha Capital" with company admin "Priya"
    And the firm "Zeta Capital" with company admin "Zed"
    And "Zeta Capital" has a deal investor "Zeta Hidden Investor"
    And "Alpha Capital" has a kanban card "Follow up" sourced from the deal investor "Zeta Hidden Investor"
    And "Priya" is signed in
    When they open the kanban card "Follow up"
    Then the page loads
    And the response mentions "Follow up"
    And the response does not mention "Zeta Hidden Investor"
    When they open the kanban card "Follow up" in its side panel
    Then the page loads
    And the response does not mention "Zeta Hidden Investor"

  # F2-2H — Happy path: a card sourced from the firm's own deal investor still links it
  @rack_test
  Scenario: F2-2H A kanban card links the firm's own deal investor
    Given the firm "Alpha Capital" with company admin "Priya"
    And "Alpha Capital" has a deal investor "Alpha Lead Investor"
    And "Alpha Capital" has a kanban card "Follow up" sourced from the deal investor "Alpha Lead Investor"
    And "Priya" is signed in
    When they open the kanban card "Follow up"
    Then the response mentions "Alpha Lead Investor"
    When they open the kanban card "Follow up" in its side panel
    Then the response mentions "Alpha Lead Investor"

  # ---- F3 CiProfile rich text ----------------------------------------------------------------

  # F3-1 — Edge case: script, event handlers, iframes and javascript: links in CiProfile details are dropped; the formatting is kept (F3-H)
  Scenario: F3-1 CiProfile details are sanitized in the investment solutions layout
    When the investment solutions page renders a profile whose details are "<strong>Growth</strong> fund<script>alert(1)</script><img src=x onerror=alert(2)><iframe src='https://evil.example'></iframe><a href='javascript:alert(3)'>Deck</a>"
    Then the rendered profile details keep "<strong>Growth</strong> fund"
    And the rendered profile details have no script, image, iframe, event handler or javascript link

  # ---- F4 Portfolio report agent's firm ------------------------------------------------------

  # F4-1 — Edge case: the analyst who wrote the report now belongs to another firm; the section is generated by the agent of the company's firm, and no agent is made in the analyst's firm
  Scenario: F4-1 The section agent belongs to the portfolio company's firm, not the analyst's
    Given Im logged in as a user "first_name=Gita" for an entity "name=Artha;entity_type=Investment Fund"
    And a portfolio company "Artha Robotics" exists
    And the AI portfolio report on "Artha Robotics" was written by an analyst now at "Zeta Capital"
    When a text section of that report is generated
    Then the section was generated by the portfolio report agent of "Artha"
    And "Zeta Capital" has no portfolio report agent

  # ---- F5 Pre-existing bugs found during the review (steps: security_followups_b_steps.rb) --------

  Rule: F5 — only the selling firm allocates an interest or verifies an allocation (H19's firm-side rule)

    Background:
      Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Company"
      And the user has role "company_admin"
      And there is a sale "name=Grand Sale"
      And the sale has a seller with an approved offer and a buyer with a short-listed interest

    # F5-1 — Edge case: a buyer allocating and verifying their own interest is refused, and nothing changes
    @rack_test
    Scenario: F5-1 A buyer cannot allocate their own interest
      Given "Y" has an unverified interest on the sale
      When "Y" allocates their interest with "allocation_quantity=7;verified=1"
      Then I am denied access
      And the interest of "Y" has "verified=false;allocation_quantity=0"

    # F5-1H — Happy path: the sale's company admin allocates an interest (raised NoMethodError for everyone before)
    @rack_test
    Scenario: F5-1H The sale's company admin allocates an interest
      Given "Y" has an unverified interest on the sale
      When the sale's company admin allocates the interest of "Y" with "allocation_quantity=7;verified=1"
      Then the interest of "Y" has "verified=true;allocation_quantity=7"

    # F5-1X — Edge case: offers#allocate had a route but no action; the address is gone
    @rack_test
    Scenario: F5-1X The old offer allocate address is not found
      When the sale's company admin patches the old allocate address of the seller's offer
      Then the address is not found
      And the "offers" routes have no "allocate, allocation_form" action

    # F5-2 — Edge case: the seller and the buyer of an allocation cannot verify it
    @rack_test
    Scenario Outline: F5-2 A seller or buyer cannot verify their allocation
      Given the sale has allocations "X->Y"
      When "<party>" verifies the allocation "X->Y"
      Then I am denied access
      And the allocation "X->Y" is not verified

      Examples:
        | party |
        | X     |
        | Y     |

    # F5-2H — Happy path: the sale's company admin verifies an allocation (raised NoMethodError for everyone before)
    @rack_test
    Scenario: F5-2H The sale's company admin verifies an allocation
      Given the sale has allocations "X->Y"
      When the sale's company admin verifies the allocation "X->Y"
      Then the allocation "X->Y" is verified

  Rule: F5 — a new board gets each configured column once

    # F5-3 — Edge case: BoardsController#create added the columns again after KanbanBoard#post_create_ops made them
    @rack_test
    Scenario: F5-3 A new board has each column once
      Given the firm "Alpha Capital" with company admin "Priya"
      And "Alpha Capital" boards start with the columns "Todo, In Progress, Done"
      And "Priya" is signed in
      When they create a board "Alpha Pipeline"
      Then the board "Alpha Pipeline" has the columns "Todo, In Progress, Done"

  Rule: F5 — the LP assistant reads portfolio company rows as stored, and its LIMIT always applies

    Background:
      Given Im logged in as a user "" for an entity "entity_type=Investment Fund;currency=INR"
      And the user has role "company_admin"
      And there is a fund "name=Growth Fund I;currency=INR;show_portfolios=true" for the entity
      And the fund has the LP allocation formulas
      And the fund "Growth Fund I" holds:
        | company        | instrument    | purchases | cost_cr | fmv_cr |
        | Acme Robotics  | Series B CCPS | 1         | 25.00   | 40.00  |
        | Bluefin Health | Series A CCPS | 1         | 20.00   | 22.00  |
      And LP "Ravi Menon" has folio "F-012" in "Growth Fund I"
      And folio "F-012" has allocation entries:
        | formula                  | company       | instrument    | amount |
        | Allocated Portfolio Cost | Acme Robotics | Series B CCPS | 2.50   |
      And the fund "Growth Fund I" LP portfolio view is "allocated" with allocation formula "Allocated Portfolio Cost"

    # F5-5 — Edge case: the portfolio skill's valuation query filtered owner_type 'PortfolioCompany' and found nothing; it now returns the visible company's valuation, never the hidden one's
    Scenario: F5-5 The latest valuation example returns the visible portfolio company
      Given the portfolio company "Acme Robotics" has a valuation of "40.00" crore on "2025-03-31"
      And the portfolio company "Bluefin Health" has a valuation of "22.00" crore on "2025-03-31"
      When LP "Ravi Menon" runs the "portfolio" skill example "Latest valuation for each portco"
      Then the assistant answer should name "Acme Robotics"
      And the assistant answer should not name "Bluefin Health"

    # F5-5a — Edge case: portfolio company ratios are owner_type 'Investor' rows; both skills' examples return the visible company's, never the hidden one's
    Scenario Outline: F5-5a The portfolio company ratio examples return the visible portfolio company
      Given the fund "Growth Fund I" has a latest "MOIC" ratio "1.60 x" for the portfolio company "Acme Robotics"
      And the fund "Growth Fund I" has a latest "MOIC" ratio "1.10 x" for the portfolio company "Bluefin Health"
      When LP "Ravi Menon" runs the "<skill>" skill example "<question>"
      Then the assistant answer should name "Acme Robotics, 1.60 x"
      And the assistant answer should not name "Bluefin Health, 1.10 x"

      Examples:
        | skill       | question                                     |
        | portfolio   | MOIC per portfolio company in Growth Fund    |
        | fund_ratios | What is the IRR and MOIC of each portfolio company? |

    # F5-6 — Edge case: a trailing -- comment, a comment after the ";", an unclosed /* or a LIMIT only in a subquery no longer leaves the query unlimited
    Scenario Outline: F5-6 The row limit applies whatever ends the model's query
      When LP "Ravi Menon" runs the assistant query "<query>" and the statement is kept
      Then the assistant answer should name "Growth Fund I"
      And the statement the assistant ran ends with its own "LIMIT 100" line
      And the statement the assistant ran has no comment and no other "LIMIT 100"

      Examples:
        | query                                                                                                                              |
        | SELECT f.name FROM funds f WHERE f.entity_id IN ({ENTITY_ID}) AND f.id IN ({FUND_IDS}) -- the LP's funds                          |
        | SELECT f.name FROM funds f WHERE f.entity_id IN ({ENTITY_ID}) AND f.id IN ({FUND_IDS}); -- done                                    |
        | SELECT f.name FROM funds f WHERE f.entity_id IN ({ENTITY_ID}) AND f.id IN ({FUND_IDS}) /* unclosed note                            |
        | SELECT f.name FROM funds f WHERE f.entity_id IN ({ENTITY_ID}) AND f.id IN (SELECT x.id FROM funds x WHERE x.id IN ({FUND_IDS}) LIMIT 1) |

    # F5-6H — Happy path: the model's own trailing LIMIT is kept, comments and literals as written
    Scenario: F5-6H The model's own LIMIT is kept
      When LP "Ravi Menon" runs the assistant query "SELECT f.name, '-- not a comment' AS note FROM funds f WHERE f.entity_id IN ({ENTITY_ID}) AND f.id IN ({FUND_IDS}) LIMIT 5 -- top five" and the statement is kept
      Then the assistant answer should name "Growth Fund I, -- not a comment"
      And the statement the assistant ran ends with "LIMIT 5"

  Rule: F5 — routes, throttles and sample files point at things that exist

    # F5-4 — Edge case: kyc_datas had a fetch_ckyc_data route with no action (CKYC data is fetched through investor_kycs)
    Scenario: F5-4 kyc_datas routes only to its controller's actions
      Then the "kyc_datas" routes have no "fetch_ckyc_data" action
      And every "kyc_datas" route points at an action of its controller

    # F5-7 — Edge case: four formulas of the allocate_account_entries sample workbook used custom_fields.send(...), which FundFormula's safe-eval check refuses; they now use the hash lookup migration 20260904060000 wrote to the DB
    Scenario: F5-7 The sample fund formulas workbook has no custom_fields.send
      Then every formula in the sample workbook "allocate_account_entries/fund_formulas.xlsx" passes the fund formula safety check
      And 4 formulas in the sample workbook "allocate_account_entries/fund_formulas.xlsx" read "capital_commitment.custom_fields[custom_field_key.to_s]"

    # F5-8 — Edge case: the OAuth client throttle listed /oauth/introspect, which is not routed since introspection is off (M2)
    Scenario: F5-8 The OAuth client throttle lists only routed endpoints
      Then Rack::Attack does not list "/oauth/introspect" as an OAuth client path
      And every OAuth client path Rack::Attack throttles is routed
