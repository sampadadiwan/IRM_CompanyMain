class AddRatioTypeToFundRatio < ActiveRecord::Migration[7.0]
  def change
    add_reference :fund_ratios, :owner, polymorphic: true, null: true
  end
end
