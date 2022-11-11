class AddSigTypeToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :signature_type, :string, limit: 20
    safety_assured {remove_column :documents, :adhaar_esign_enabled}
    safety_assured {remove_column :documents, :adhaar_esign_completed}
  end
end
