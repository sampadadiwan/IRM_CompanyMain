class UpdateLabelInESignatures < ActiveRecord::Migration[7.1]
  # update label limit from 20 chars to 30 chars
  def change
    change_column :e_signatures, :label, :string, limit: 30
  end
end
