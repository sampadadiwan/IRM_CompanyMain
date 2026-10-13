# Accrued performance fee for a class with a class-level high-water mark.
#   hurdle-adjusted mark = mark × (1 + hurdle % × days since the last crystallisation ÷ 365)
#   hard hurdle: fee % × max(0, NAV/unit before fee − hurdle-adjusted mark) × units
#   soft hurdle: fee % × (NAV/unit before fee − mark) × units, once NAV/unit beats the hurdle-adjusted mark
# Pure function. Worked examples H29, E38, E39, E40, E41, E42 — openspec/changes/open-ended-funds/design.md#worked-examples
class PerformanceFeeCalculator
  Result = Data.define(:fee_cents, :hurdle_adjusted_cents)

  def self.accrued(term:, nav_per_unit_before_cents:, hwm_cents:, units:, days:)
    zero = Result.new(fee_cents: 0.to_d, hurdle_adjusted_cents: hwm_cents)
    return zero unless term.performance_fee? && hwm_cents.present? && units.to_d.positive?

    hwm = hwm_cents.to_d
    nav = nav_per_unit_before_cents.to_d
    hurdle_adjusted = (hwm * (1 + (term.hurdle_pct.to_d / 100 * days.to_i / 365))).round(4)
    rate = term.perf_fee_pct.to_d / 100

    gain_per_unit = if term.hurdle_type == "soft"
                      nav > hurdle_adjusted ? nav - hwm : 0
                    else
                      [nav - hurdle_adjusted, 0].max
                    end
    Result.new(fee_cents: (rate * gain_per_unit.to_d * units.to_d).round(2), hurdle_adjusted_cents: hurdle_adjusted)
  end
end
