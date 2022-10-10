class AddSignatureDataToInterest < ActiveRecord::Migration[7.0]
  def change
    add_column :interests, :signature_data, :text
  end
end
