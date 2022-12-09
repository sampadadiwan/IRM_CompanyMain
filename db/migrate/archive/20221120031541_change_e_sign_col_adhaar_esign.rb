class ChangeESignColAdhaarEsign < ActiveRecord::Migration[7.0]
  def change
    change_column :adhaar_esigns, :esign_doc_id, :string, :limit => 100
  end
end
