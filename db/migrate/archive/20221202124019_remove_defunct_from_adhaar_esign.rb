class RemoveDefunctFromAdhaarEsign < ActiveRecord::Migration[7.0]
  def change    
    remove_column :adhaar_esigns, :user_ids
    remove_column :adhaar_esigns, :completed_ids
    remove_column :adhaar_esigns, :reason
    remove_column :adhaar_esigns, :esign_url
  end
end
