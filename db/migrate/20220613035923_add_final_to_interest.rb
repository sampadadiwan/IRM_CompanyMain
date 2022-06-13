class AddFinalToInterest < ActiveRecord::Migration[7.0]
  def change
    add_column :interests, :buyer_entity_name, :string, limit: 100
    add_column :interests, :address, :text
    add_column :interests, :contact_name, :string, limit: 50
    add_column :interests, :email, :string, limit: 40
    add_column :interests, :PAN, :string, limit: 15
    add_column :interests, :final_agreement, :boolean, default: false
    add_column :offers, :final_agreement, :boolean, default: false
  end
end
