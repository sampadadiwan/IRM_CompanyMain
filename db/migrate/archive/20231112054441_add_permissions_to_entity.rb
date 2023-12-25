class AddPermissionsToEntity < ActiveRecord::Migration[7.1]
  def change
    add_column :entities, :permissions, :integer

    # For each entity, we are migrating the old individual permissions to the new permissions using active flags
    Entity.all.each do |entity|
      "enable_documents enable_deals enable_investments enable_holdings enable_secondary_sale enable_funds enable_inv_opportunities enable_options enable_captable enable_investors enable_account_entries enable_units enable_fund_portfolios enable_kpis enable_kycs enable_support enable_approvals".split(" ").each do |permission|
        puts "Setting permission #{permission} for entity #{entity.id}"
        if entity.send("#{permission}")
          entity.permissions.set(permission.to_sym) 
        else
          entity.permissions.unset(permission.to_sym) 
        end
        entity.save!
      end
    end

  end
end
