class AddInvestorToEoi < ActiveRecord::Migration[7.0]
  def change
    add_reference :expression_of_interests, :investor, null: false, foreign_key: true
  end
end
