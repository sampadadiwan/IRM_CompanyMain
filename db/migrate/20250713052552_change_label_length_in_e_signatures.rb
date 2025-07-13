class ChangeLabelLengthInESignatures < ActiveRecord::Migration[8.0]
  def change
    change_column :e_signatures, :label, :string, limit: 50    
  end
end
