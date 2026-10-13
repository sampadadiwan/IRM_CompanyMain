# What each evergreen NAV accounted for (management fee accruals and its share of fee payments) and the
# approver's late-fee decisions on a draft — so a fee booked into an already-approved period is found by
# sums alone and decided, never lost (R9.10–R9.18).
# openspec/changes/evergreen-late-management-fees/design.md#data-model-and-schema-changes
class AddLateFeeColumnsToFundNavs < ActiveRecord::Migration[8.1]
  def up
    change_table :fund_navs, bulk: true do |t|
      t.decimal :mgmt_fee_accounted_cents, precision: 20, scale: 2, default: 0, null: false
      t.decimal :mgmt_fee_paid_accounted_cents, precision: 20, scale: 2, default: 0, null: false
      t.json :late_fee_decisions
    end
    FundNav.reset_column_information
    backfill
  end

  def down
    change_table :fund_navs, bulk: true do |t|
      t.remove :late_fee_decisions, :mgmt_fee_paid_accounted_cents, :mgmt_fee_accounted_cents
    end
  end

  private

  # R9.18: a NAV approved before these rules took in exactly its own period's fees, as drafted. Uploaded
  # NAVs stay 0 — they reset the window (the administrator's figure includes the fee).
  def backfill
    FundNav.approved.where(source: "computed").distinct.pluck(:fund_id, :unit_type).each do |fund_id, unit_type|
      fund = Fund.find(fund_id)
      prev = nil
      FundNav.approved.where(fund_id:, unit_type:).order(:nav_date).each do |nav|
        backfill_one(fund, nav, prev) if nav.source == "computed"
        prev = nav
      end
    end
  end

  def backfill_one(fund, nav, prev)
    saved = nav.breakdown.to_h
    # Window accruals: what the draft saved, else the ledger window as it stands now
    ledger = NavInputs.new(fund, nav.nav_date).mgmt_fee_accrued_cents(nav.unit_type, prev&.nav_date)
    accrued = saved["mgmt_fee_accrued_cents"]&.to_d || ledger
    say("fund_nav #{nav.id}: ledger window #{ledger.to_s('F')} differs from drafted #{accrued.to_s('F')}") if (ledger - accrued).abs > 1 # cents; sub-cent rounding is expected
    # Payments: what the draft saved, else what the payable implies (previous + accrued − paid = payable)
    paid = saved["mgmt_fee_paid_cents"]&.to_d || [prev&.mgmt_fee_payable_cents.to_d + accrued - nav.mgmt_fee_payable_cents.to_d, 0].max
    nav.update_columns(mgmt_fee_accounted_cents: accrued.round(2), mgmt_fee_paid_accounted_cents: paid.round(2))
  end
end
