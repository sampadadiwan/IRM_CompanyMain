class AddExchangeRateToCommitmentAdjustment < ActiveRecord::Migration[7.0]
  def change
    add_reference :commitment_adjustments, :owner, polymorphic: true, null: true
  end
end
