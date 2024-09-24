class ChangeOfferHoldingOptional < ActiveRecord::Migration[7.1]
  def change
    change_column_null :offers, :holding_id, true
  end
end
