# Part-paid subscriptions accepted at the amount received (open-ended-funds § Accept received amount):
# the amount originally asked for, and who reduced it when.
class AddAcceptedAmountToDealingOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :dealing_orders, :original_amount_cents, :decimal, precision: 20, scale: 2
    add_reference :dealing_orders, :amount_reduced_by, foreign_key: { to_table: :users }
    add_column :dealing_orders, :amount_reduced_at, :datetime
  end
end
