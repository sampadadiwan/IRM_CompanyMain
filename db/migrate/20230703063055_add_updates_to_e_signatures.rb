class AddUpdatesToESignatures < ActiveRecord::Migration[7.0]
  def change
    add_column :e_signatures, :updates, :text
  end
end
