class DropRemittanceGenerationBasis < ActiveRecord::Migration[7.2]
  def change
    remove_column :funds, :remittance_generation_basis
  end
end
