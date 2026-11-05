Feature: MCP tools return only the caller's own firm's and own folio's data
  WHY THIS FEATURE EXISTS
  The MCP server lets an external AI client (Claude, ChatGPT, …) read fund data over an OAuth
  bearer token. The October 2026 security review marked it "checked and found safe" because every
  tool starts from `Pundit.policy_scope(user, …)` (docs/security/security_review_2026_10.md,
  "Checked and found safe"). That was a code reading. No scenario ever proved it.
  features/ai/mcp_server/ only tests the ontology (filters and sorts) and the transport.

  That matters because:
    * there are 23 tools over 16 entities, each written separately in FundAssistantDataManager /
      PortfolioAssistantDataManager. One new tool, or one refactor, that starts from `Model.all`
      or `find(id)` instead of the policy scope leaks every firm's data;
    * a leak here is silent: the AI client presents another firm's rows as a normal answer;
    * MCP can be enabled for LPs (entity_setting.mcp_allowed_roles_list offers "investor"), so the
      LP-vs-LP boundary matters as much as the firm boundary.

  The tools are called directly (Tool.call(server_context: …)), the same way McpController#create
  calls them after authentication. Token, OAuth and governance checks are covered by
  features/api/oauth_clients.feature and tenant_isolation_batch2 (B4-5). This feature is only
  about which rows a tool returns once it runs.

  Two firms are built the same way, so every refused row has a matching row the caller IS
  allowed to see. A check is never green just because the table was empty.

  Background:
    Given a fund firm "Zeta Capital" with the fund "Zeta Fund" and LPs "Zeta LP One"
    And a fund firm "Artha" with the fund "Artha Select" and LPs "Kiran, Meera"
    And I act over MCP as Artha's company admin

  # MCP-1 — Error case: a list tool never returns another firm's rows, even when the call names the
  #   other firm's fund id in fund_ids (and it still returns the caller's own rows).
  #   Why: the list tools are the widest read. A missing policy_scope would hand back Zeta's funds,
  #   commitments (with LP names and amounts), calls, remittances, distributions or portfolio companies.
  @security
  Scenario Outline: MCP-1 <tool> returns Artha's rows and none of Zeta's
    When I call the "<tool>" MCP tool for every fund, mine and Zeta's
    Then every row it returns belongs to "Artha"
    And it returns at least one of Artha's rows
    And it returns none of "Zeta Capital"'s rows, although Zeta has some

    Examples:
      | tool                        |
      | list_funds                  |
      | list_capital_commitments    |
      | list_capital_calls          |
      | list_capital_remittances    |
      | list_capital_distributions  |
      | list_portfolio_companies    |

  # MCP-2 — Error case: a get-by-id tool refuses another firm's record id.
  #   Why: ids are sequential and an AI client will happily try any id a user types. get_document
  #   would also hand out the file's signed URL.
  @security
  Scenario Outline: MCP-2 <tool> refuses Zeta's <record>
    When I call the "<tool>" MCP tool for Zeta Capital's <record>
    Then the MCP answer does not reveal Zeta Capital's <record>

    Examples:
      | tool                          | record            |
      | get_fund_details              | fund              |
      | get_commitment_details        | commitment        |
      | get_document                  | document          |
      | get_portfolio_company_details | portfolio company |

  # MCP-2H — Happy path: the same get tools return Artha's own records (so MCP-2 is a real refusal).
  @security
  Scenario Outline: MCP-2H <tool> returns Artha's own <record>
    When I call the "<tool>" MCP tool for Artha's <record>
    Then the MCP answer names Artha's <record>

    Examples:
      | tool                          | record            |
      | get_fund_details              | fund              |
      | get_commitment_details        | commitment        |
      | get_document                  | document          |
      | get_portfolio_company_details | portfolio company |

  # MCP-3 — Edge case: get_document looks a document up by NAME, with a LIKE fallback.
  #   Why: a name lookup is the classic way scoping gets lost: `Document.find_by(name:)` ignores ids
  #   and firms entirely. Zeta's document name is unique, so any hit is a leak.
  @security
  Scenario: MCP-3 Looking a document up by another firm's document name finds nothing
    When I call get_document by the name of Zeta Capital's document
    Then the MCP answer does not reveal Zeta Capital's document

  # MCP-4 — Edge case: list_account_entries only aggregates (it refuses individual rows), so a leak
  #   would show up as a count or total that includes another firm's ledger.
  #   Why: account_entries is the largest table (CLAUDE.md), and a cross-firm SUM looks like a valid number.
  @security
  Scenario: MCP-4 Counting account entries counts only Artha's ledger
    When I count account entries over MCP
    Then the count equals Artha's own account entries, not including Zeta's

  # MCP-5 — Error case: an LP sees only their own folios, never another LP of the same fund.
  #   Why: LP-vs-LP isolation within one fund (ForInvestor) was the root cause of H11, H18 and M23 on
  #   the web screens. MCP reads the same models, so it needs the same guarantee.
  @security
  Scenario Outline: MCP-5 An LP's <tool> returns only their own folios
    Given I act over MCP as the LP user of "Kiran"
    When I call the "<tool>" MCP tool for every fund, mine and Zeta's
    Then it returns at least one of Kiran's rows
    And every row it returns is Kiran's, none Meera's

    Examples:
      | tool                     |
      | list_capital_commitments |
      | list_capital_remittances |

  # MCP-6 — Error case: an LP cannot open another LP's commitment by id.
  #   Why: the commitment carries the other LP's name, amounts and folio. This is the by-id variant of MCP-5.
  @security
  Scenario: MCP-6 An LP cannot read another LP's commitment, but can read their own
    Given I act over MCP as the LP user of "Kiran"
    When I call get_commitment_details for Meera's commitment
    Then the MCP answer does not reveal Meera's commitment
    When I call get_commitment_details for Kiran's commitment
    Then the MCP answer names Kiran's commitment
