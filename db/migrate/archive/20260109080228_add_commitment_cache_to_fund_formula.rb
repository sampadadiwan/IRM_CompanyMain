class AddCommitmentCacheToFundFormula < ActiveRecord::Migration[8.0]
  def change
    add_column :fund_formulas, :add_to_commitment_cache, :boolean, default: true, null: false
    FundFormula.update_all(add_to_commitment_cache: true)
  end
end
