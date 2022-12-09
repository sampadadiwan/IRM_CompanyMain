class AddPpmNoToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :ppm_number, :bigint, default: 0
  end
end
