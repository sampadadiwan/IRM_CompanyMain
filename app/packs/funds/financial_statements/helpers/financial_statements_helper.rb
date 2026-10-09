# View helpers for the Financial Statements pages: amounts, status and check badges, and the
# "Immediate Actions" confirm-popup cards (custom/action_summary_modal.scss) for Lock and Regenerate.
module FinancialStatementsHelper
  STATE_BADGES = {
    "generating" => ["bg-info-subtle text-info", "Generating…"],
    "failed" => ["bg-danger-subtle text-danger", "Failed"],
    "ready" => ["bg-warning-subtle text-warning", "Draft"],
    "locked" => ["bg-success-subtle text-success", "Locked"]
  }.freeze

  # Plain-language explanation of each check and warning: the tooltip (short) and the "How checks
  # work" popup (question, how it's worked out, when skipped, what a failure usually means)
  CHECK_HELP = {
    "balance" => {
      short: "Assets − liabilities − partners' capital must be 0: the statements add up",
      question: "Do the statements add up — Assets = Liabilities + Partners' capital?",
      how: "Total assets − total liabilities − partners' capital (contributions − distributions + the P&L result since the fund started).",
      skipped: "Never skipped.",
      fails: "A line is missing (often an Unmapped entry), counted twice, or stored with the wrong sign. If the difference is twice one account's figure, flip that account's sign."
    },
    "nav" => {
      short: "Partners' capital must equal the fund's NAV entry (set on Settings)",
      question: "Do the statements agree with the NAV the fund reports?",
      how: "Partners' capital − the latest value of the NAV entry chosen on Settings, on or before the end date.",
      skipped: "When no NAV entry is set on Settings, or the fund has no such entry on or before the end date.",
      fails: "The NAV formula sees different entries from the statements — usually an entry the NAV includes but the mapping excludes or misses — or the NAV entry wasn't updated for the period."
    },
    "capital" => {
      short: "The investors' capital accounts must add up to partners' capital",
      question: "Do the investors' capital accounts add up to the fund's partners' capital?",
      how: "Partners' capital − the sum, over every folio, of the latest value of the capital entry chosen on Settings.",
      skipped: "When no capital entry is set on Settings.",
      fails: "An allocation didn't reach every folio, or a fund-level entry on the statements was never allocated to investors. Check the period's accounting allocation run."
    },
    "roll_forward" => {
      short: "Opening capital + this period's movements must equal closing capital",
      question: "Does partners' capital move correctly from the start of the period to the end?",
      how: "Opening partners' capital + every movement on the Statement of Changes in Partners' Capital (contributions, distributions, the P&L result) − closing partners' capital.",
      skipped: "When the Statement of Changes in Partners' Capital has no account rows.",
      fails: "A capital movement (e.g. Distributions) isn't on the Changes statement. Add it on the Layout tab; the difference is that movement's amount."
    },
    "stale_balance" => { short: "A running-total entry has nothing dated in the period, so its last value is used" },
    "no_entries" => { short: "An account on a statement that no entry feeds — it prints 0" },
    "mixed_cumulative" => { short: "An entry is stored both as a running total and as movements; the running total is used" }
  }.freeze

  def fs_check_help(check)
    CHECK_HELP.fetch(check["key"], {})
  end

  # Draft entries overview order: entries not used first, then used, then excluded
  DRAFT_ENTRY_ORDER = { unused: 0, line: 1, excluded: 2 }.freeze

  # Lock popup marks per check status
  LOCK_CHECK_MARKS = { "passed" => "✓", "skipped" => "–", "failed" => "✗" }.freeze

  CHECK_BADGES = {
    "passed" => %w[text-success ti-circle-check Passed],
    "failed" => %w[text-danger ti-circle-x Failed],
    "skipped" => %w[text-muted ti-circle-minus Skipped],
    "warning" => %w[text-warning ti-alert-triangle Warning]
  }.freeze

  # Cents in the fund's currency, negatives in brackets ("($45,200)"); whole units on statements.
  # The brackets are added here: money_to_currency keeps the minus sign inside them for Money values.
  def fs_amount(cents, fund, decimals: 0)
    return "" if cents.nil?

    cents = cents.to_d
    formatted = money_to_currency(Money.new(cents.abs, fund.currency), {}, true, decimals:)
    cents.negative? ? "(#{formatted})" : formatted
  end

  # Draft / Generating / Failed / Locked, plus "changed since locked" for a drifted locked set
  def fs_state_badge(statement, drifted: false)
    css, label = STATE_BADGES.fetch(statement.state)
    badge = tag.span(label, class: "badge #{css}")
    return badge unless drifted

    # safe_join keeps the badges as HTML (string interpolation would escape them)
    safe_join([badge, tag.span(safe_join([tag.i(class: "ti ti-alert-triangle"), " Changed since locked"]), class: "badge bg-warning-subtle text-warning")], " ")
  end

  def fs_check_icon(check)
    css, icon, label = CHECK_BADGES.fetch(check["status"])
    tag.span(tag.i(class: "ti #{icon}") + " #{label}", class: css)
  end

  def fs_check_label(check)
    FinancialStatementCalculator::CHECK_LABELS.fetch(check["key"], check["key"].to_s.humanize)
  end

  # "3/4 ✓" for the list: passed out of the checks that ran (skipped ones don't count against)
  def fs_checks_summary(statement)
    checks = statement.integrity_checks
    return tag.span("—", class: "text-muted") if checks.empty?

    failed = checks.count { |c| c["status"] == "failed" }
    ran = checks.count { |c| c["status"] != "skipped" }
    css = failed.positive? ? "text-danger" : "text-success"
    icon = failed.positive? ? "ti-circle-x" : "ti-circle-check"
    tag.span(tag.i(class: "ti #{icon}") + " #{ran - failed}/#{ran} passed", class: css)
  end

  def fs_action_summary(cards, intro_action:)
    intro = tag.div(class: "action-summary__intro") do
      tag.div("Immediate Actions", class: "fw-bold text-dark") +
        tag.div(safe_join(["The following will happen when you click", " ", tag.strong(intro_action), ":"]), class: "text-muted")
    end
    items = cards.map do |tint, icon, title, desc|
      tag.div(class: "action-summary__item action-summary__item--#{tint}") do
        tag.span(tag.i(class: "ti #{icon}"), class: "action-summary__icon") +
          tag.div(tag.div(title, class: "action-summary__title") + tag.div(desc, class: "action-summary__desc"))
      end
    end
    intro + tag.div(safe_join(items), class: "action-summary__list")
  end

  # Lock popup: what freezes, what it means, and any completeness warnings to confirm (V10–V12)
  def fs_lock_action_summary(statement)
    fs_action_summary([
                        ["green", "ti-lock", "Figures frozen",
                         "Every line of every statement for #{statement.period_label} is kept as published; next year's prior-period columns use these figures"],
                        ["purple", "ti-shield-lock", "Allocation runs protected",
                         "The statements run is locked; unlocking this period's allocation runs will warn first and notify Fund accounting"],
                        ["blue", "ti-eye", "What you'll see",
                         "\"Locked on … by you\"; Excel / PDF use the frozen figures; if entries change later a \"Changed since locked\" banner appears"],
                        ["amber", "ti-list-check", "Checked before locking", fs_lock_preconditions_text(statement)]
                      ], intro_action: "Lock")
  end

  # The lock gate (FinancialStatement#lockable_with_reason) as ✓ lines, plus the warnings being confirmed
  def fs_lock_preconditions_text(statement)
    lines = statement.integrity_checks.map do |check|
      mark = LOCK_CHECK_MARKS[check["status"]]
      "#{mark} #{fs_check_label(check)}#{' (skipped)' if check['status'] == 'skipped'}"
    end
    lines << "#{statement.unmapped_count.zero? ? '✓' : '✗'} Nothing unmapped"
    warnings = statement.warning_checks
    lines << "#{pluralize(warnings.size, 'warning')} you are confirming: #{warnings.pluck('note').join('; ').truncate(220)}" if warnings.any?
    lines.join(" · ")
  end

  # Generate popup: what runs, what is written, what you'll see, and the preconditions checked live
  # (by FinancialStatementGenerate's own rules). The covering accounting run depends on the dates
  # chosen, so the latest completed one is named.
  def fs_generate_action_summary(fund)
    pre = FinancialStatementGenerate.preconditions(fund)
    fs_action_summary([
                        ["blue", "ti-player-play", "Statements run starts",
                         "A separate allocation run runs only the statement formula for the period — your accounting formulas and entries are not touched"],
                        ["green", "ti-file-plus", "Statement lines saved",
                         "Every line is calculated from the fund's entries and mapping and saved as an \"FS · …\" entry dated the end date"],
                        ["purple", "ti-eye", "What you'll see",
                         "The set opens as Generating…, then Draft with its checks and Unmapped count; nothing is published until you Lock"],
                        ["amber", "ti-list-check", "Needs before it starts", fs_preconditions_text(pre)]
                      ], intro_action: "Generate statements")
  end

  # Regenerate popup: same cards for an existing Draft, with the accounting run checked for its own period
  def fs_regenerate_action_summary(statement)
    pre = FinancialStatementGenerate.preconditions(statement.fund)
    covered = FinancialStatementGenerate.accounting_runs(AllocationRun.where(fund_id: statement.fund_id))
                                        .exists?(["start_date <= ? AND end_date >= ?", statement.start_date, statement.end_date])
    fs_action_summary([
                        ["blue", "ti-refresh", "Lines recalculated",
                         "A new statements run rewrites this period's \"FS · …\" lines from the current entries and mapping"],
                        ["green", "ti-checks", "Checks re-run", "Checks and the Unmapped count refresh when the run finishes; the set stays Draft"],
                        ["purple", "ti-database", "Nothing else changes", "Accounting entries and other periods' statements are untouched"],
                        ["amber", "ti-list-check", "Needs before it starts", fs_preconditions_text(pre, covered:, period: statement.period_label)]
                      ], intro_action: "Regenerate")
  end

  # "✓ … · ✗ …" — each precondition Generate checks, and whether it holds right now
  def fs_preconditions_text(pre, covered: nil, period: nil)
    latest = pre[:latest_accounting_run]
    accounting = if !covered.nil?
                   "Completed accounting run covering #{period}"
                 elsif latest
                   "Completed accounting run covering the period (latest: #{l(latest.start_date)} – #{l(latest.end_date)})"
                 else
                   "Completed accounting run covering the period (none yet)"
                 end
    accounting_ok = covered.nil? ? latest.present? : covered
    [
      "#{accounting_ok ? '✓' : '✗'} #{accounting}",
      "#{pre[:run_in_progress] ? '✗' : '✓'} No allocation run in progress",
      "#{pre[:formula_enabled] ? '✓' : '✗'} Statement formula enabled",
      "If any is missing it stops and says why"
    ].join(" · ")
  end

  # Allocation-run Unlock popup when locked statement sets overlap (H16): runs unlocked, the sets
  # back to Draft, Fund accounting notified
  def fs_unlock_action_summary(statements, runs_text:)
    periods = statements.map(&:period_label).to_sentence
    fs_action_summary([
                        ["amber", "ti-lock-open", "Runs unlocked", runs_text],
                        ["red", "ti-file-alert", "Statements back to Draft", "Locked financial statements for #{periods} return to Draft; what was published is kept"],
                        ["blue", "ti-bell", "Fund accounting notified", "Users tagged FundAccounting get an email and an in-app alert"]
                      ], intro_action: "Proceed")
  end

  # "Move to" choices on the AI draft, grouped by statement, with short line labels
  def fs_draft_move_options(suggestion, selected)
    groups = suggestion.account_lines.group_by { |l| l["statement_title"] }.transform_values do |lines|
      lines.map { |l| [l["label"], l["key"]] }
    end
    groups["Not on a statement"] = [["Excluded (not on any statement)", FinancialStatementMappingSuggestion::EXCLUDED],
                                    ["Not placed yet", FinancialStatementMappingSuggestion::UNPLACED]]
    grouped_options_for_select(groups, selected)
  end

  # "Add an entry…" choices for an account line nothing feeds: entries not used yet first, then the rest
  def fs_draft_entry_options(suggestion)
    unplaced = fs_draft_entries_overview(suggestion).select { |e| e[:state] == :unused }.map { |e| [e[:entry_type], e[:name]] }
    all = fs_draft_entry_pairs(suggestion)
    value = ->(pair) { pair.join(FinancialStatementMappingSuggestion::ENTRY_SEPARATOR) }
    groups = {}
    groups["Not placed on any line"] = unplaced.map { |pair| [pair.join(" · "), value.call(pair)] } if unplaced.any?
    groups["All entries"] = (all - unplaced).map { |pair| [pair.join(" · "), value.call(pair)] }
    grouped_options_for_select(groups)
  end

  # What a calculated draft row is (no entries feed it directly)
  def fs_draft_row_note(suggestion, line)
    case line["role"]
    when "subtotal"
      labels = suggestion.lines.select { |l| line["subtotal_of"].include?(l["key"]) }.pluck("label")
      labels.any? ? "Adds up: #{labels.join(' + ')}" : "Total (adds up the lines above)"
    when "net_result" then "Calculated by CapHive: income − expenses + gains"
    when "opening" then "Calculated by CapHive: partners' capital at the start"
    when "closing" then "Calculated by CapHive: partners' capital at the end"
    end
  end

  # ---- AI draft review screen: which account entries feed each printed line (mapping only) ----
  # The draft never compares amounts: users upload whatever statement they have, and the outcome is
  # the mapping. Figures are checked later by the statements' own checks.

  # Entry pairs the draft knows (the fund's fund-level entries)
  def fs_draft_entry_pairs(suggestion)
    @fs_draft_entry_pairs ||= Array(suggestion.proposal_data["entries"]).map { |e| [e["entry_type"], e["name"]] }
  end

  # The entries feeding a line, as "entry type · name" labels. An any-name rule lists every entry of
  # that type (except names another rule maps exactly).
  def fs_draft_line_entries(suggestion, line)
    exact = Array(suggestion.proposal_data["rules"]).reject { |r| r["name"].blank? }.to_set { |r| [r["entry_type"], r["name"]] }
    suggestion.rules_for(line["key"]).flat_map do |rule|
      if rule["name"].present?
        ["#{rule['entry_type']} · #{rule['name']}"]
      else
        names = fs_draft_entry_pairs(suggestion).select { |type, name| type == rule["entry_type"] && exact.exclude?([type, name]) }
        names.any? ? names.map { |type, name| "#{type} · #{name}" } : ["#{rule['entry_type']} · (every name)"]
      end
    end
  end

  # The same account shown on another statement whose entries are mapped there
  def fs_draft_twin(suggestion, line)
    suggestion.account_lines.find { |l| l["label"] == line["label"] && l["key"] != line["key"] && suggestion.rules_for(l["key"]).any? }
  end

  # [css, status, what to do] for one printed line — about the mapping only
  def fs_draft_line_action(suggestion, line)
    if line["role"] != "account"
      ["info", "Calculated", "Nothing to map — CapHive works this out from the other lines."]
    elsif suggestion.rules_for(line["key"]).any?
      ["success", "Mapped", nil]
    elsif (twin = fs_draft_twin(suggestion, line))
      ["info", "Mapped on another statement", "Same account as on #{twin['statement_title'].to_s.truncate(40)} — nothing to do here."]
    else
      ["danger", "No entries yet",
       "Add the account entry that makes up this line — or leave it empty if CapHive doesn't hold this figure."]
    end
  end

  # Status badge as on the grids (art_status_badge style): badge bg-X-subtle text-X with a leading icon
  DRAFT_STATUS_ICONS = { "success" => "ti-circle-check", "danger" => "ti-alert-triangle", "info" => "ti-calculator" }.freeze
  def fs_draft_status_badge(color, label, icon: nil)
    icon ||= DRAFT_STATUS_ICONS.fetch(color, "ti-info-circle")
    tag.span(safe_join([tag.i(class: "ti #{icon} me-1"), label]), class: "badge bg-#{color}-subtle text-#{color}")
  end

  # Where an entry goes, as a badge on the "By account entry" tab
  def fs_draft_entry_badge(entry)
    case entry[:state]
    when :line then fs_draft_status_badge("success", "Mapped → #{entry[:goes_to]&.dig('label')}")
    when :excluded then fs_draft_status_badge("info", "Excluded — not a statement figure", icon: "ti-ban")
    else fs_draft_status_badge("danger", "Not used — choose a line or Excluded")
    end
  end

  # Row id of an entry on the "By account entry" tab (for links and redirects)
  def fs_draft_entry_anchor(entry_type, name)
    "entry-#{"#{entry_type}-#{name}".parameterize}"
  end

  # Every entry the draft knows and where it goes: [{ entry_type:, name:, rule_name:, goes_to:, state: }]
  # state: :line / :excluded / :unused
  def fs_draft_entries_overview(suggestion)
    data = suggestion.proposal_data
    lines_by_key = suggestion.lines.index_by { |l| l["key"] }
    exact = Array(data["rules"]).reject { |r| r["name"].blank? }.index_by { |r| [r["entry_type"], r["name"]] }
    any_name = Array(data["rules"]).select { |r| r["name"].blank? }.index_by { |r| r["entry_type"] }
    excluded = Array(data["excluded"]).to_set { |r| [r["entry_type"], r["name"].to_s] }
    fs_draft_entry_pairs(suggestion).map do |type, name|
      rule = exact[[type, name]] || any_name[type]
      state, goes_to = if rule then [:line, lines_by_key[rule["line"]]]
                       elsif excluded.include?([type, name]) || excluded.include?([type, ""]) then [:excluded, nil]
                       else [:unused, nil]
                       end
      { entry_type: type, name:, rule_name: rule ? rule["name"].to_s : name, goes_to:, state: }
    end.sort_by { |e| [DRAFT_ENTRY_ORDER[e[:state]], e[:entry_type], e[:name]] }
  end

  # Link to the Mapping tab previewing a statement set's period (to fix its Unmapped entries)
  def fs_mapping_path_for(statement)
    financial_statement_mappings_path(fund_id: statement.fund_id, period_start: statement.start_date, period_end: statement.end_date)
  end
end
