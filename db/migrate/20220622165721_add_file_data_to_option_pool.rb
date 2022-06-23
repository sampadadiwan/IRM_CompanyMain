class AddFileDataToOptionPool < ActiveRecord::Migration[7.0]
  def change
    add_column :option_pools, :certificate_signature_data, :text
    add_column :offers, :signature_data, :text
    add_column :offers, :spa_data, :text
    add_column :offers, :id_proof_data, :text
    add_column :offers, :address_proof_data, :text
    add_column :interests, :spa_data, :text
  end
end
