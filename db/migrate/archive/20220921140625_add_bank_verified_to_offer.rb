class AddBankVerifiedToOffer < ActiveRecord::Migration[7.0]
  def change
    add_column :offers, :bank_verified, :boolean, default: false
    add_column :offers, :bank_verification_response, :text
    add_column :offers, :bank_verification_status, :string
  end
end
