# On a class's crystallisation date, turns the NAV's accrued performance fee into ledger entries
# ("Performance Fee Crystallised", one per class folio, split by units held, parent = the FundNav)
# and moves the high-water mark up to the NAV per unit after the fee, if higher.
# Off-schedule NAVs, or a zero accrual, crystallise nothing.
# Worked examples H30, E43 — openspec/changes/open-ended-funds/design.md#worked-examples
class Crystalliser
  ENTRY_NAME = "Performance Fee Crystallised".freeze
  ENTRY_TYPE = "Performance Fees".freeze
  BATCH = 500

  def self.call(fund_nav:)
    term = fund_nav.fund.evergreen_class_terms.find_by(unit_type: fund_nav.unit_type)
    return 0 unless term&.perf_fee_model == "class_hwm" && term.crystallisation_date?(fund_nav.nav_date)

    fee = fund_nav.perf_fee_accrued_cents.to_d
    # Nothing accrued: nothing crystallises, and the mark / hurdle clock stay where they are
    return 0 unless fee.positive?

    new_mark = [fund_nav.hwm_cents.to_d, fund_nav.nav_per_unit_cents.to_d].max
    inserted = insert_entries(fund_nav, fee)
    fund_nav.update!(crystallised: true, hwm_after_cents: new_mark)
    inserted
  end

  # One commitment-level entry per folio of the class, split by units held on the NAV date
  def self.insert_entries(fund_nav, fee)
    units = FundUnit.where(fund_id: fund_nav.fund_id, unit_type: fund_nav.unit_type, issue_date: ..fund_nav.nav_date)
                    .group(:capital_commitment_id).sum(:quantity).select { |_, q| q.to_d.positive? }
    total = units.values.sum.to_d
    return 0 if total.zero?

    folios = CapitalCommitment.where(id: units.keys).pluck(:id, :investor_id, :folio_id).index_by(&:first)
    now = Time.current
    rows = units.map do |cc_id, qty|
      _, investor_id, folio_id = folios[cc_id]
      { entity_id: fund_nav.entity_id, fund_id: fund_nav.fund_id, capital_commitment_id: cc_id, investor_id:, folio_id:,
        name: ENTRY_NAME, entry_type: ENTRY_TYPE, reporting_date: fund_nav.nav_date, period: "As of Date",
        amount_cents: (fee * qty.to_d / total).round(2), parent_type: "FundNav", parent_id: fund_nav.id,
        generated: true, created_at: now, updated_at: now }
    end
    rows.each_slice(BATCH) { |batch| AccountEntry.insert_all(batch) }
    rows.size
  end

  # Reopen: remove this NAV's crystallisation entries (fund + date + parent, indexed) and the mark
  def self.reverse(fund_nav)
    AccountEntry.where(fund_id: fund_nav.fund_id, reporting_date: fund_nav.nav_date, parent_type: "FundNav", parent_id: fund_nav.id).delete_all
    fund_nav.update!(crystallised: false, hwm_after_cents: nil)
  end
end
