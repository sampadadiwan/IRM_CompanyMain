# Evergreen (open-ended) funds: six new tables, nothing added to existing tables.
# The existence of an evergreen_fund_settings row is the fund's evergreen flag; dealing dates
# and fills link to existing settlement records (capital calls/distributions, remittances,
# payments, fund units) from the new side only.
# Backward compatibility B1–B8 — openspec/changes/open-ended-funds/design.md#backward-compatibility
class CreateEvergreenTables < ActiveRecord::Migration[8.1]
  def change
    # ① The fund's evergreen terms (fund-level defaults for class-overridable terms)
    create_table :evergreen_fund_settings do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true, index: { unique: true }
      t.string :subscription_calendar, limit: 15, null: false, default: "monthly"
      t.json :subscription_dates
      t.string :redemption_calendar, limit: 15, null: false, default: "quarterly"
      t.json :redemption_dates
      t.string :dealing_day, limit: 10, null: false, default: "first"
      t.integer :dealing_day_n
      t.string :payment_timing, limit: 10, null: false, default: "before"
      t.integer :pay_after_days, null: false, default: 7
      t.integer :subscription_cutoff_days, null: false, default: 5
      t.string :unready_handling, limit: 10, null: false, default: "roll"
      t.string :order_journeys, limit: 15, null: false, default: "off"
      t.references :subscription_journey_template, foreign_key: { to_table: :workflow_templates }
      t.references :redemption_journey_template, foreign_key: { to_table: :workflow_templates }
      t.json :redemption_forms
      t.integer :redemption_settlement_days, null: false, default: 10
      t.integer :notice_days, null: false, default: 30
      t.integer :lock_up_months, null: false, default: 0
      t.string :lock_up_type, limit: 5, null: false, default: "hard"
      t.json :early_redemption_fee
      t.decimal :min_initial_subscription_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :min_additional_subscription_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :min_holding_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :gate_pct, precision: 7, scale: 4, null: false, default: 0
      t.string :gate_level, limit: 5, null: false, default: "fund"
      t.string :gate_period, limit: 15, null: false, default: "dealing_date"
      t.string :gate_method, limit: 10, null: false, default: "pro_rata"
      t.decimal :investor_gate_pct, precision: 7, scale: 4, null: false, default: 0
      t.string :cash_entry_name, limit: 125, null: false, default: "Cash In Hand"
      t.string :other_assets_entry_name, limit: 125, null: false, default: "Net Current Assets"
      t.string :other_liabilities_entry_name, limit: 125, null: false, default: "Other Liabilities"
      t.string :mgmt_fee_paid_entry_name, limit: 125, null: false, default: "Management Fee Paid"
      t.string :perf_fee_paid_entry_name, limit: 125, null: false, default: "Performance Fee Paid"
      t.string :fund_close_name, null: false, default: "Evergreen"
      t.text :payment_instructions
      t.references :contract_note_template, foreign_key: { to_table: :documents }
      t.references :redemption_advice_template, foreign_key: { to_table: :documents }
      t.string :preset, limit: 40
      t.references :enabled_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    # ① Per-class terms; null overrides fall back to the fund value
    create_table :evergreen_class_terms do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true, index: false
      t.references :evergreen_fund_setting, null: false, foreign_key: true
      t.string :unit_type, limit: 40, null: false
      t.decimal :initial_price_cents, precision: 24, scale: 4
      t.string :perf_fee_model, limit: 15, null: false, default: "none"
      t.decimal :perf_fee_pct, precision: 7, scale: 4, null: false, default: 0
      t.decimal :hurdle_pct, precision: 7, scale: 4, null: false, default: 0
      t.string :hurdle_type, limit: 5, null: false, default: "hard"
      t.string :crystallisation, limit: 15, null: false, default: "annual"
      t.integer :notice_days
      t.integer :lock_up_months
      t.string :lock_up_type, limit: 5
      t.json :early_redemption_fee
      t.decimal :min_initial_subscription_cents, precision: 20, scale: 2
      t.decimal :min_additional_subscription_cents, precision: 20, scale: 2
      t.decimal :min_holding_cents, precision: 20, scale: 2
      t.timestamps
      t.index %i[fund_id unit_type], unique: true
    end

    # ③④ NAV per class per date (draft / approved), every line kept for audit
    create_table :fund_navs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true, index: false
      t.string :unit_type, limit: 40, null: false
      t.date :nav_date, null: false
      t.string :status, limit: 10, null: false, default: "draft"
      t.string :source, limit: 10, null: false, default: "computed"
      t.decimal :investments_fmv_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :cash_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :other_assets_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :mgmt_fee_payable_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :perf_fee_payable_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :perf_fee_accrued_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :other_liabilities_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :nav_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :units_outstanding, precision: 26, scale: 8, null: false, default: 0
      t.decimal :nav_per_unit_before_perf_cents, precision: 24, scale: 4
      t.decimal :nav_per_unit_cents, precision: 24, scale: 4
      t.decimal :class_share, precision: 12, scale: 10, null: false, default: 1
      t.decimal :hwm_cents, precision: 24, scale: 4
      t.decimal :hwm_after_cents, precision: 24, scale: 4
      t.boolean :crystallised, null: false, default: false
      t.date :mgmt_fee_accrued_to
      t.json :overrides
      t.json :breakdown
      t.string :inputs_fingerprint, limit: 64
      t.references :prepared_by, foreign_key: { to_table: :users }
      t.references :approved_by, foreign_key: { to_table: :users }
      t.datetime :approved_at
      t.references :import_upload
      t.timestamps
      # One NAV per class per date; drafts are hard-deleted, approved NAVs are never deleted
      t.index %i[fund_id unit_type nav_date], unique: true
      t.index %i[fund_id unit_type status nav_date]
    end

    # ⑤ One record per fund per dealing date: step bar, confirmed snapshot, settlement links
    create_table :dealing_dates do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true, index: false
      t.date :date, null: false
      t.datetime :cutoff_at, null: false
      t.boolean :has_subscriptions, null: false, default: false
      t.boolean :has_redemptions, null: false, default: false
      t.string :payment_timing, limit: 10, null: false
      t.string :status, limit: 10, null: false, default: "open"
      t.references :subscription_call, foreign_key: { to_table: :capital_calls }
      t.references :redemption_distribution, foreign_key: { to_table: :capital_distributions }
      t.json :settings_snapshot
      t.json :gate_snapshot
      t.references :confirmed_by, foreign_key: { to_table: :users }
      t.datetime :confirmed_at
      t.references :closed_by, foreign_key: { to_table: :users }
      t.datetime :closed_at
      t.timestamps
      t.index %i[fund_id date], unique: true
      t.index %i[fund_id status]
    end

    # ② Subscription and redemption orders
    create_table :dealing_orders do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true, index: false
      t.references :investor, null: false, foreign_key: true
      t.references :capital_commitment, foreign_key: true
      t.references :dealing_date, null: false, foreign_key: true
      t.references :capital_remittance, foreign_key: true
      t.string :unit_type, limit: 40, null: false
      t.string :kind, limit: 12, null: false
      t.string :status, limit: 20, null: false, default: "pending"
      t.decimal :amount_cents, precision: 20, scale: 2
      t.decimal :units, precision: 26, scale: 8
      t.boolean :all_units, null: false, default: false
      t.datetime :received_at, null: false
      t.integer :rolled_count, null: false, default: 0
      t.string :source, limit: 10, null: false, default: "portal"
      t.references :entered_by, foreign_key: { to_table: :users }
      t.references :import_upload
      t.decimal :early_fee_pct, precision: 7, scale: 4, null: false, default: 0
      t.decimal :locked_units, precision: 26, scale: 8, null: false, default: 0
      t.references :accepted_by, foreign_key: { to_table: :users }
      t.datetime :accepted_at
      t.string :rejected_reason
      t.references :signatory_verified_by, foreign_key: { to_table: :users }
      t.datetime :signatory_verified_at
      t.references :cancelled_by, foreign_key: { to_table: :users }
      t.datetime :cancelled_at
      t.text :note
      t.timestamps
      t.index %i[fund_id kind status received_at]
    end

    # ⑤ What each order got on a dealing date, frozen at confirm
    create_table :dealing_fills do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :dealing_date, null: false, foreign_key: true, index: false
      t.references :dealing_order, null: false, foreign_key: true
      t.references :fund_nav, foreign_key: true
      t.string :kind, limit: 12, null: false
      t.string :unit_type, limit: 40, null: false
      t.decimal :requested_units, precision: 26, scale: 8, null: false, default: 0
      t.decimal :units, precision: 26, scale: 8, null: false, default: 0
      t.decimal :carried_units, precision: 26, scale: 8, null: false, default: 0
      t.decimal :amount_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :early_fee_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :nav_per_unit_cents, precision: 24, scale: 4, null: false
      t.references :capital_remittance, foreign_key: true
      t.references :capital_distribution_payment, foreign_key: true
      t.references :fund_unit, foreign_key: true
      t.references :document, foreign_key: true
      t.datetime :instructions_sent_at
      t.datetime :document_sent_at
      t.timestamps
      t.index %i[dealing_date_id dealing_order_id], unique: true
    end
  end
end
