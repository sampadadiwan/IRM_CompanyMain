# The two allocation formulas a fund picks for its LP portfolio view: the allocation formula decides which
# holdings an LP sees (and is "Your cost" under own share); the FMV formula is "Your FMV". Both nullify when
# the formula is deleted so the fund row stays valid and LPs simply lose that view (E6, E6a).
# openspec/changes/lp-folio-portfolio-dashboard/design.md#data-model-and-schema-changes
class AddLpPortfolioPicksToFunds < ActiveRecord::Migration[8.1]
  def change
    add_reference :funds, :lp_allocation_fund_formula, foreign_key: { to_table: :fund_formulas, on_delete: :nullify }, null: true
    add_reference :funds, :lp_fmv_fund_formula, foreign_key: { to_table: :fund_formulas, on_delete: :nullify }, null: true
  end
end
