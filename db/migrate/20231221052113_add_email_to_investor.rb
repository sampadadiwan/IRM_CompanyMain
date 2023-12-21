class AddEmailToInvestor < ActiveRecord::Migration[7.1]
  def change
    add_column :investors, :primary_email, :string
    add_column :entities, :primary_email, :string

    Investor.where(primary_email: nil).each do |inv|
      primary_email = inv.investor_accesses.first&.email&.presence || inv.investor_entity.employees.first&.email
      inv.update_column(:primary_email, primary_email)
    end
    
    Entity.where(primary_email: nil).each do |entity|
      primary_email = entity.employees.first&.email
      entity.update_column(:primary_email, primary_email)
    end
    
  end
end
