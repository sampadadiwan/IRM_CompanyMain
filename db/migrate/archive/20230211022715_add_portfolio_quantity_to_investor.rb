class AddPortfolioQuantityToInvestor < ActiveRecord::Migration[7.0]
  def change
    add_reference :portfolio_investments, :document_folder, null: true, foreign_key: {to_table: :folders}
  end
end
