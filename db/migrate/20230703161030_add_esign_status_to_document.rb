class AddEsignStatusToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :esign_status, :string, limit: 20
  end
end
