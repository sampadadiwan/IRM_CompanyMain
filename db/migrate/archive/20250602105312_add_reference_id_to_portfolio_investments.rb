class AddReferenceIdToPortfolioInvestments < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:portfolio_investments, :ref_id)
      add_column :portfolio_investments, :ref_id, :bigint, null: false, default: 0
    end
  end
end
