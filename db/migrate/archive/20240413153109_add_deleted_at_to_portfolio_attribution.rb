class AddDeletedAtToPortfolioAttribution < ActiveRecord::Migration[7.1]
  def change
    add_column :portfolio_attributions, :deleted_at, :datetime
    add_index :portfolio_attributions, :deleted_at
  end
end
