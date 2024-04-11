class AddCapitalCommitmentsCountToFunds < ActiveRecord::Migration[7.1]
  def self.up
    add_column :funds, :capital_commitments_count, :integer, null: false, default: 0

    CapitalCommitment.counter_culture_fix_counts only: :fund, batch_size: 100
  end

  def self.down
    remove_column :funds, :capital_commitments_count
  end
end
