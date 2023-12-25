class DropEnableFieldsForEntity < ActiveRecord::Migration[7.1]
  COLS = %i[enable_documents enable_deals enable_investments enable_holdings enable_secondary_sale enable_funds enable_inv_opportunities enable_options enable_captable enable_investors enable_account_entries enable_units enable_fund_portfolios enable_kpis enable_kycs enable_support enable_approvals].freeze
  
  def up
    COLS.each do |column_name|
      remove_column :entities, column_name.to_sym
    end
  end

  def down
    COLS.each do |column_name|
      add_column :entities, column_name.to_sym, :boolean, default: false
    end

    Entity.all.each do |entity|
      COLS.each do |column_name|
        entity["#{column_name}"] = true if entity.permissions.send("#{column_name}?")
      end
    end
  end
end
