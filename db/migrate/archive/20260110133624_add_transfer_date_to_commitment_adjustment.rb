class AddTransferDateToCommitmentAdjustment < ActiveRecord::Migration[8.0]
  def change
    add_column :commitment_adjustments, :transfer_date, :date
  end
end
