class AddInvestorToMessage < ActiveRecord::Migration[7.0]
  def change
    add_reference :messages, :investor, null: true, foreign_key: true
  end
end
