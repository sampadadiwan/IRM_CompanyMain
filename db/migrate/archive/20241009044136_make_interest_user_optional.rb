class MakeInterestUserOptional < ActiveRecord::Migration[7.1]
  def change
    change_column_null :interests, :user_id, true
  end
end
