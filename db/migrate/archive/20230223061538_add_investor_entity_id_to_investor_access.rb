class AddInvestorEntityIdToInvestorAccess < ActiveRecord::Migration[7.0]
  def change
    add_reference :investor_accesses, :investor_entity, null: true, foreign_key: {to_table: :entities}
    InvestorAccess.all.each do |ia|
      ia.investor_entity_id = ia.investor.investor_entity_id
      ia.save
    end
  end
end
