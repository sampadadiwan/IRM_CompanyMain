class AddIndexesForPortfolioFmvQuery < ActiveRecord::Migration[8.0]
  def up
    # add_index :portfolio_investments,
    #           [:portfolio_company_id, :id],
    #           name: "idx_pi_company_id_id"

    # add_index :account_entries,
    #           [:parent_type, :parent_id, :fund_id, :name, :deleted_at, :cumulative],
    #           name: "idx_ae_parent_fund_name_flags"
  end

  def down
    # remove_index :portfolio_investments, name: "idx_pi_company_id_id"
    # remove_index :account_entries, name: "idx_ae_parent_fund_name_flags"
  end
end
