class AddExcusedInvestorsToPortfolioInvestments < ActiveRecord::Migration[8.0]
  def up
    add_column :portfolio_investments, :excused_folio_ids, :json, null: false
  end

  def down
    remove_column :portfolio_investments, :excused_folio_ids, :json
  end
end
