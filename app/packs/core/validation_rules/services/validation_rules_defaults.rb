# Canonical list of default validation rules, shared between:
#   - lib/tasks/validation_rules.rake  (seed_defaults task)
#   - features/support/validation_rules_seed.rb  (Cucumber test setup)
#
# Edit here only — the rake task and test seed reference this constant directly
# so there is a single source of truth.
module ValidationRulesDefaults
  DEFAULT_RULES = [
    # ── Valuation ──────────────────────────────────────────────────────────────
    {
      name: "valuation_date_not_quarter_end",
      target_model: "Valuation",
      description: "Warns when the valuation date does not fall on the last day of a calendar quarter (Mar 31, Jun 30, Sep 30, Dec 31).",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          { "field" => "valuation_date", "op" => "not_quarter_end" }
        ]
      },
      params: {},
      severity: "warning",
      message_template: "Valuation date %{valuation_date} is not a quarter-end date. Please confirm this is intentional."
    },
    {
      name: "valuation_large_increase",
      target_model: "Valuation",
      description: "Warns when the new per-share value is more than pct_threshold % higher than the previous one for the same instrument.",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          {
            "field" => "per_share_value_cents",
            "op" => "pct_change_gt",
            "param" => "pct_threshold",
            "compare_to" => "context.prev_per_share_value_cents"
          }
        ]
      },
      params: { "pct_threshold" => 50 },
      severity: "warning",
      message_template: "Per-share value has increased by more than %{pct_threshold}%% compared to the previous valuation for this instrument. Please confirm."
    },
    {
      name: "valuation_large_decrease",
      target_model: "Valuation",
      description: "Warns when the new per-share value is more than pct_threshold % lower than the previous one for the same instrument.",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          {
            "field" => "per_share_value_cents",
            "op" => "pct_change_lt",
            "param" => "pct_threshold",
            "compare_to" => "context.prev_per_share_value_cents"
          }
        ]
      },
      params: { "pct_threshold" => 50 },
      severity: "warning",
      message_template: "Per-share value has decreased by more than %{pct_threshold}%% compared to the previous valuation for this instrument. Please confirm."
    },

    # ── AllocationRun ──────────────────────────────────────────────────────────
    {
      name: "allocation_run_date_not_quarter_end",
      target_model: "AllocationRun",
      description: "Warns when the allocation run end date does not fall on a quarter-end.",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          { "field" => "end_date", "op" => "not_quarter_end" }
        ]
      },
      params: {},
      severity: "warning",
      message_template: "Allocation run end date %{end_date} is not a quarter-end date. Please confirm this is intentional."
    },
    {
      name: "allocation_run_already_locked",
      target_model: "AllocationRun",
      description: "Blocks saving when the allocation run record is already locked.",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          { "field" => "locked", "op" => "eq", "value" => true }
        ]
      },
      params: {},
      severity: "blocker",
      message_template: "This allocation run is locked and cannot be modified."
    },
    {
      name: "allocation_run_valuation_exists",
      target_model: "AllocationRun",
      description: "Warns when any of the fund's portfolio companies is missing a valuation within n_days days prior to the allocation run end date.",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          { "field" => "end_date", "op" => "not_blank" },
          { "field" => "context.missing_valuation_companies", "op" => "not_blank" }
        ]
      },
      params: { "n_days" => 30 },
      severity: "warning",
      message_template: "Valuations missing for: %{missing_valuation_companies} (no valuation in the last %{n_days} days before %{end_date}). Please upload valuations before running the allocation."
    },
    {
      name: "allocation_run_fx_rates_exist",
      target_model: "AllocationRun",
      description: "Warns when FX rates are missing within n_days days prior to the allocation run end date. Checks instrument currencies → fund currency, feeder currencies → fund currency, and fund currency → tracking currency (if set).",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          { "field" => "end_date", "op" => "not_blank" },
          { "field" => "context.missing_fx_rates", "op" => "not_blank" }
        ]
      },
      params: { "n_days" => 5 },
      severity: "warning",
      message_template: "FX rates missing: %{missing_fx_rates} — no rate found in the last %{n_days} days before %{end_date}. Please upload exchange rates before running the allocation."
    },
    {
      name: "allocation_run_account_entries_exist",
      target_model: "AllocationRun",
      description: "Warns when required account entries (comma-separated names in account_entry_names) are missing within n_days days prior to the allocation run end date. Inactive until account_entry_names is configured (default is empty = disabled).",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          { "field" => "end_date",                      "op" => "not_blank" },
          { "field" => "context.account_entries_exist", "op" => "eq", "value" => false }
        ]
      },
      params: { "n_days" => 30, "account_entry_names" => "" },
      severity: "warning",
      message_template: "Required account entries (%{account_entry_names}) not found in the %{n_days} days before the run end date (%{end_date}). Please ensure all required entries are imported."
    },

    # ── CapitalCall ───────────────────────────────────────────────────────────
    {
      name: "capital_call_notices_not_generated",
      target_model: "CapitalCall",
      enabled: true,
      description: "Warns when one or more remittances have no generated call notice document (owner_tag: Generated).",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          { "field" => "context.remittances_without_notices", "op" => "not_blank" }
        ]
      },
      params: {},
      severity: "warning",
      message_template: "Call notices have not been generated for: %{remittances_without_notices}. Please generate documents for these remittances."
    },
    {
      name: "capital_call_notices_not_approved",
      target_model: "CapitalCall",
      enabled: true,
      description: "Blocks approval when generated call notice documents are pending approval.",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          { "field" => "context.unapproved_notices_count", "op" => "not_blank" }
        ]
      },
      params: {},
      severity: "blocker",
      message_template: "There are %{unapproved_notices_count} generated call notice(s) pending approval. Please approve all documents before approving this call."
    },
    {
      name: "capital_call_investors_without_notification_subscribers",
      target_model: "CapitalCall",
      enabled: true,
      # Warning, not blocker: an unsubscribed investor doesn't stop the call from being approved,
      # only from being notified — surfacing it here (rather than only reactively when a Send
      # Call Notification button greys out) is what Open Question 6 asked for; it should not add
      # a new gate to Approve itself.
      description: "Warns when one or more investors on the call have nobody subscribed to Capital Call notifications, so this is caught before it silently blocks a send.",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          { "field" => "context.investors_without_notification_subscribers", "op" => "not_blank" }
        ]
      },
      params: {},
      severity: "warning",
      message_template: "No investor contacts are subscribed to Capital Call notifications for: %{investors_without_notification_subscribers}. They will not receive the call notice until a contact is subscribed."
    },

    # ── CapitalCommitment ─────────────────────────────────────────────────────
    {
      name: "capital_commitment_investor_without_notification_subscribers",
      target_model: "CapitalCommitment",
      enabled: true,
      # The commitment-time half of the Question 6 proactive check (the other half is the
      # CapitalCall rule above). Warning only — it must never stop an investor being added.
      description: "Warns when a commitment is added for an investor who has nobody subscribed to Capital Call notifications, so the gap is caught at onboarding rather than at send time.",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          { "field" => "context.investor_without_subscribers", "op" => "not_blank" }
        ]
      },
      params: {},
      severity: "warning",
      message_template: "No investor contacts are subscribed to Capital Call notifications for %{investor_without_subscribers} — they will not receive call notices until a contact is subscribed."
    },

    # ── CapitalRemittance ─────────────────────────────────────────────────────
    {
      name: "capital_remittance_notice_not_generated",
      target_model: "CapitalRemittance",
      enabled: true,
      description: "Warns when the remittance has no generated call notice document (owner_tag: Generated).",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          { "field" => "context.notice_not_generated", "op" => "not_blank" }
        ]
      },
      params: {},
      severity: "warning",
      message_template: "A call notice has not been generated for this remittance. Please generate the document before sending the notification."
    },
    {
      name: "capital_remittance_notice_not_approved",
      target_model: "CapitalRemittance",
      enabled: true,
      description: "Blocks sending notification when the remittance's generated call notice is pending approval.",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          { "field" => "context.notice_not_approved", "op" => "not_blank" }
        ]
      },
      params: {},
      severity: "blocker",
      message_template: "There are %{notice_not_approved} generated call notice(s) for this remittance pending approval. Please approve the document before sending the notification."
    },

    # ── FundRatioRunTemplate ───────────────────────────────────────────────────
    {
      name: "fund_ratio_run_template_date_not_quarter_end",
      target_model: "FundRatioRunTemplate",
      description: "Warns when the run template trigger date does not fall on a quarter-end.",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          { "field" => "trigger_end_date", "op" => "not_quarter_end" }
        ]
      },
      params: {},
      severity: "warning",
      message_template: "Run template trigger date %{trigger_end_date} is not a quarter-end date. Please confirm this is intentional."
    },

    # ── FundRatio ──────────────────────────────────────────────────────────────
    {
      name: "fund_ratio_date_not_quarter_end",
      target_model: "FundRatio",
      description: "Warns when the fund ratio end date does not fall on a quarter-end.",
      condition_tree: {
        "op" => "AND",
        "conditions" => [
          { "field" => "end_date", "op" => "not_quarter_end" }
        ]
      },
      params: {},
      severity: "warning",
      message_template: "Fund ratio end date %{end_date} is not a quarter-end date. Please confirm this is intentional."
    }
  ].freeze
end
