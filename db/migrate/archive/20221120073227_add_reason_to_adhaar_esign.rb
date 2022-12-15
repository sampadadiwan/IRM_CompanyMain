class AddReasonToAdhaarEsign < ActiveRecord::Migration[7.0]
  def change
    add_column :adhaar_esigns, :reason, :string
    add_column :documents, :locked, :boolean, default: false
  end
end
