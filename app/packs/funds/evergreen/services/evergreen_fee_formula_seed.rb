# Adds the ready-made "Management Fee on NAV" fund formula (design card ⑧): per folio,
#   NAV per unit (latest approved on or before the period start) × units held × class fee % × days ÷ 365
# so the fee is charged on NAV and allocated by units held. Runs in allocation runs like any formula.
# Worked examples H27, E37 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenFeeFormulaSeed
  NAME = "Management Fee on NAV".freeze
  FORMULA = "(fund.evergreen_nav_per_unit_cents(capital_commitment.unit_type, start_date) || 0) * @units * " \
            "(fund_unit_setting ? fund_unit_setting.management_fee.to_d : 0) / 100 * ((end_date - start_date).to_i + 1) / 365".freeze

  # Returns [formula, created?]
  def self.call(fund)
    existing = fund.fund_formulas.find_by(name: NAME)
    return [existing, false] if existing

    ApplicationRecord.safe_eval!(FORMULA, context: NAME)
    sequence = fund.fund_formulas.maximum(:sequence).to_i + 1
    formula = fund.fund_formulas.create!(
      entity_id: fund.entity_id, name: NAME, rule_type: "GenerateAccountEntry", entry_type: NavInputs::MGMT_FEE_ENTRY_TYPE,
      rule_for: "Accounting", enabled: true, sequence:, formula: FORMULA,
      description: "Evergreen management fee: class fee % on NAV per unit × units held, for the days in the period."
    )
    [formula, true]
  end
end
