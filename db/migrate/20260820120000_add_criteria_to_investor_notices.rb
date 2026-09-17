# criteria is a Dentaku expression (same [bracket.path] syntax as
# ReportBuilderFormulaService), evaluated at render time per viewing investor —
# see InvestorNoticeCriteriaEvaluator. Blank/nil means "always show", so every
# existing notice keeps its current behavior unchanged.
class AddCriteriaToInvestorNotices < ActiveRecord::Migration[8.1]
  def change
    add_column :investor_notices, :criteria, :text
  end
end
