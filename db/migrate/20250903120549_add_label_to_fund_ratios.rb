class AddLabelToFundRatios < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:fund_ratios, :label)
      add_column :fund_ratios, :label, :string, limit: 50
    end
  end
end
