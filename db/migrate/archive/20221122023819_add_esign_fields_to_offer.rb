class AddEsignFieldsToOffer < ActiveRecord::Migration[7.0]
  def change
    add_column :offers, :esign_required, :boolean, default: false
    add_column :offers, :esign_completed, :boolean, default: false
    add_column :offers, :esign_provider, :string, limit: 10
    add_column :offers, :esign_link, :string
    add_column :offers, :seller_signature_types, :string, limit: 20, default: ""
    add_column :interests, :buyer_signature_types, :string, limit: 20, default: ""
  end
end
