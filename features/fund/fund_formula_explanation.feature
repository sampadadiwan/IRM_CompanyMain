Feature: FundFormula parse_statement explanation breakdown
  parse_statement evaluates a formula against a live binding and returns an ordered
  Hash of { expression => value } pairs. The breakdown is stored on AccountEntry and
  drives both the UI calculation steps table and the AI explanation prompt.

  Different formula shapes need different extraction strategies:
  - Single-expression formulas expose every intermediate sub-expression.
  - Multi-statement formulas collapse assignments to their variable names and
    recursively expand any bare final expression.
  Arrays, string literals, AR objects, and self-naming constants are handled
  specially to keep the breakdown signal-to-noise ratio high.


  # ─── Single-expression formulas ────────────────────────────────────────────

  Scenario: Single-expression formula captures every intermediate sub-expression
    # Without named intermediate variables the sub-expressions ARE the explanation.
    # Sorting by key length (shortest first) reads as a build-up from simple to final.
    Given a formula "@base_cents * @rate / 100" with bindings "base_cents=1000000;rate=2.0"
    When parse_statement is run on the formula
    Then the breakdown includes the key "@base_cents" with numeric value 1000000.0
    And the breakdown includes the key "@rate" with numeric value 2.0
    And the breakdown includes the key "@base_cents * @rate" with numeric value 2000000.0
    And the breakdown includes the key "@base_cents * @rate / 100" with numeric value 20000.0
    And the breakdown does not include any bare numeric literal keys


  # ─── Multi-statement formulas — assignment nodes ────────────────────────────

  Scenario: Multi-statement formula — assignment nodes collapse to variable names
    # Each "x = complex_expression" line becomes one entry keyed by "x".
    # The RHS complexity is intentionally hidden — the author named it for a reason.
    Given a multi-statement formula with bindings "base_cents=1000000;rate=2.0":
      """
      gross = @base_cents * @rate / 100;
      tax = gross * 0.18;
      gross + tax
      """
    When parse_statement is run on the formula
    Then the breakdown includes the key "gross" with numeric value 20000.0
    And the breakdown includes the key "tax" with numeric value 3600.0
    And the breakdown includes the key "gross + tax" with numeric value 23600.0
    And the breakdown does not include the key "@base_cents * @rate / 100"


  Scenario: Multi-statement formula — complex final expression is recursively expanded
    # The final bare expression (not an assignment) gets full sub-expression
    # extraction so every operand and intermediate product is visible.
    # The assignment above it ("fx_rate = ...") still collapses to just "fx_rate".
    Given a multi-statement formula with bindings "unrealized_cents=10000000;percentage=6.25":
      """
      fx_rate = 85.0;
      @unrealized_cents * fx_rate * @percentage / 100
      """
    When parse_statement is run on the formula
    Then the breakdown includes the key "fx_rate" with numeric value 85.0
    And the breakdown includes the key "@unrealized_cents" with numeric value 10000000.0
    And the breakdown includes the key "@unrealized_cents * fx_rate" with numeric value 850000000.0
    And the breakdown includes the key "@unrealized_cents * fx_rate * @percentage" with numeric value 5312500000.0
    And the breakdown includes the key "@unrealized_cents * fx_rate * @percentage / 100" with numeric value 53125000.0
    And the breakdown does not include the key "85.0"


  Scenario: Multi-statement formula — operand @ivars are visible when used in arithmetic
    # When an assignment RHS is "@v1 - @v2", collect_ivar_expressions previously
    # treated the whole expression as a single @ivar attribute-access and early-returned,
    # so "@v1" and "@v2" never appeared individually in the breakdown.
    # Now operator calls (-, +, *, /, etc.) fall through to recurse, capturing each operand.
    Given a multi-statement formula with bindings "committed=500000;called=150000":
      """
      uncalled = @committed - @called;
      uncalled
      """
    When parse_statement is run on the formula
    Then the breakdown includes the key "@committed" with numeric value 500000.0
    And the breakdown includes the key "@called" with numeric value 150000.0
    And the breakdown includes the key "uncalled" with numeric value 350000.0


  # ─── Array values ───────────────────────────────────────────────────────────

  Scenario: Array variables are summarised with a count and a contextual label
    # Previously arrays were silently dropped by skip_statement. Now they are
    # converted to "N <label>: [...]" using the variable name to pick the label.
    Given a multi-statement formula with no bindings:
      """
      portfolio_company_ids = [100, 200, 300];
      portfolio_company_ids.length
      """
    When parse_statement is run on the formula
    Then the breakdown includes the key "portfolio_company_ids" with string value "3 portfolio companies: [100, 200, 300]"
    And the breakdown includes the key "portfolio_company_ids.length" with numeric value 3.0

  Scenario: Large arrays are stored in full (truncation happens only in the LLM prompt)
    # The full list is preserved in the breakdown so the UI can display all IDs.
    # AccountEntryExplainerService truncates long values before building the prompt.
    Given a multi-statement formula with no bindings:
      """
      investor_ids = [1, 2, 3, 4, 5, 6, 7];
      investor_ids.length
      """
    When parse_statement is run on the formula
    Then the breakdown includes the key "investor_ids" with string value "7 investors: [1, 2, 3, 4, 5, 6, 7]"


  # ─── Noise filtering ────────────────────────────────────────────────────────

  Scenario: Bare string literal arguments are excluded from the breakdown
    # "Management" (a quoted string literal) evaluates to itself — it adds no
    # information. skip_statement detects this via /\A["'].*["']\z/ on the expression.
    Given a formula '@fee_type.start_with?("Management")' with bindings "fee_type=Management Fee"
    When parse_statement is run on the formula
    Then the breakdown includes the key "@fee_type"
    And the breakdown includes the key '@fee_type.start_with?("Management")'
    And the breakdown does not include the key '"Management"'

  Scenario: Class constant nodes that equal their own name are excluded from the breakdown
    # find_expressions captures :const nodes (e.g. Integer in @x.is_a?(Integer)).
    # skip_statement filters them when exp.delete("\"'").strip == val.to_s.strip —
    # "Integer" == Integer.to_s i.e. "Integer" == "Integer".
    Given a formula "@base_cents.is_a?(Integer)" with bindings "base_cents=1000000"
    When parse_statement is run on the formula
    Then the breakdown includes the key "@base_cents.is_a?(Integer)"
    And the breakdown does not include the key "Integer"


  # ─── reparse_and_save ───────────────────────────────────────────────────────

  Scenario: reparse_and_save pins the result key to the account entry's stored amount_cents
    # Re-evaluating the formula against the current DB can give a different value
    # than what was stored when the allocation originally ran (new records may have
    # been created since then). Pinning the result to amount_cents keeps the
    # breakdown consistent with what is actually displayed to the user.
    Given an account entry exists with formula "@base_cents * @rate / 100"
    And the account entry has amount_cents 15000
    And the account entry has bindings "base_cents=2000000;rate=5.0"
    When reparse_and_save is called on the account entry
    Then the saved breakdown result key has numeric value 15000.0
    And the live formula would evaluate to 100000.0
