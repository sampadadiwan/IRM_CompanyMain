class AddPanCardVerifiedToOffer < ActiveRecord::Migration[7.0]
  def change
    add_column :offers, :pan_verified, :boolean, default: false
    add_column :offers, :pan_verification_response, :text
    add_column :offers, :pan_verification_status, :string
  end
end
