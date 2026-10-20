# Support Console — the relay on the support machine (design card ④) and the data tool's local mode
# (card ⑦). These run the machine's own Node tests (support_console/machine/test/) against a fake
# `claude` and, for E22, the local MySQL prepared by `rake support_console:local_setup`.
# Worked examples: openspec/changes/support-console/design.md#worked-examples
Feature: Support Console relay

  # X6 — Error case: a request with a wrong HMAC signature is refused and no turn starts
  Scenario: Bad signature
    When the support machine tests matching "X6" run
    Then they pass

  # X8 — Error case: a request with a timestamp more than 60 s old is refused
  Scenario: Stale timestamp
    When the support machine tests matching "X8" run
    Then they pass

  # E22 — Edge case: local mode accepts a writable server only when the account's write probe is refused
  Scenario: Local mode needs a refused write probe
    When the support machine tests matching "E22" run
    Then they pass

  # E24 — Edge case: staging (no replica) accepts the writer when the write probe is refused; production ignores the flag
  Scenario: Staging writer allowed, production never
    When the support machine tests matching "E24" run
    Then they pass

  # E26 — Edge case: joins with repeated column names, WITH statements and trailing comments run, capped at 200 rows
  Scenario: Joins, WITH and comments run under the cap
    When the support machine tests matching "E26" run
    Then they pass

  # X15 — Error case: a comment marker inside a string cannot hide the rest of the statement from the scope check
  Scenario: Comment marker inside a string
    When the support machine tests matching "X15" run
    Then they pass

  # E30 — Edge case: "sonnet" / "opus" map to the environment's model ids; a raw id or nothing is Sonnet
  Scenario: Model names map to ids
    When the support machine tests matching "E30" run
    Then they pass

  # X16 — Error case: quoting the checker reads differently from MySQL cannot hide a filter; what runs is rebuilt from the checked parse
  Scenario: Parser-differential quoting
    When the support machine tests matching "X16" run
    Then they pass

  # X17 — Error case: every SELECT in a statement needs its own client filter — UNION arms, subqueries, derived tables, CTEs
  Scenario: Every SELECT is checked
    When the support machine tests matching "X17" run
    Then they pass

  # X18 — Error case: a second table in a comma join, a loose join or a RIGHT JOIN needs its own tie to the client
  Scenario: Joins need their own tie
    When the support machine tests matching "X18" run
    Then they pass

  # X19 — Error case: secret and cross-client tables, and other schemas, are refused outright
  Scenario: Denied tables and schemas
    When the support machine tests matching "X19" run
    Then they pass

  # X20 — Error case: locking reads, file and wait functions, and WITH … DELETE are refused even when scoped
  Scenario: Locks, files, waits, writes
    When the support machine tests matching "X20" run
    Then they pass

  # X21 — Error case: a database account holding anything beyond SELECT, SHOW VIEW or REPLICATION CLIENT is refused at connect
  Scenario: Grants beyond read-only
    When the support machine tests matching "X21" run
    Then they pass

  # X22 — Error case: Claude never inherits the relay secret, and its read tools are denied the machine's secrets and other clients
  Scenario: No secrets reach Claude
    When the support machine tests matching "X22" run
    Then they pass

  # X25 — Edge case: the relay sends the Claude session id as soon as Claude starts, before any answer
  Scenario: Session id first
    When the support machine tests matching "X25" run
    Then they pass

  # X27 — Error case: the code the machine reads is built from an allow-list and holds no keys, credentials or deploy files
  Scenario: Code archive holds no secrets
    When the code archive is built from HEAD
    Then the archive holds "app/packs" and "db/schema.rb"
    And the archive holds none of "config/deploy_id_rsa, config/deploy_id_rsa_enc, config/credentials, config/master.key, config/support_console"

  # X28 — Error case: a subscription out of usage ends the turn with usage_limit, not a generic failure
  Scenario: Usage limit reported
    When the support machine tests matching "X28" run
    Then they pass

  # X29 — Error case: an expired or revoked subscription token ends the turn with auth_failed
  Scenario: Dead token reported
    When the support machine tests matching "X29" run
    Then they pass

  # E32 — Edge case: on a subscription token the models are Claude Code's aliases and Bedrock is never switched on
  Scenario: Subscription sign-in
    When the support machine tests matching "E32" run
    Then they pass
