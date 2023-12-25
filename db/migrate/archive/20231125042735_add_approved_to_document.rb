class AddApprovedToDocument < ActiveRecord::Migration[7.1]
  def change
    add_reference :documents, :approved_by, null: true, foreign_key: { to_table: :users }
    add_column :documents, :approved, :boolean
    
  end
end
