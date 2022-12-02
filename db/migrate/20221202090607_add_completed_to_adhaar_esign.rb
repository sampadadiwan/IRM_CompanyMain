class AddCompletedToAdhaarEsign < ActiveRecord::Migration[7.0]
  def change
    add_column :adhaar_esigns, :completed_ids, :string, limit: 10
  end
end
