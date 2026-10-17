# Carries the retired per-holding Show Portfolio flag over to the company Show to LPs switch (LpCompanySwitchCarryOver).
# The old column stays populated for rollback; down leaves the switches as they are.
# Worked examples H17, E48, E49, E51, X19 — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
class CarryOverShowPortfolioToCompanies < ActiveRecord::Migration[8.1]
  def up
    Investor.reset_column_information
    result = LpCompanySwitchCarryOver.call
    say "LP company switch carry-over: changed=#{result.changed} skipped=#{result.skipped} (company deleted)"
  end

  def down
    say "Carry-over is not reversed: the company switches stay as they are (show_portfolio is untouched)."
  end
end
