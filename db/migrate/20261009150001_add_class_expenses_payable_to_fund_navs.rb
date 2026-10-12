# The class-only expenses line on a class NAV, rolled forward like the fee payables
# (evergreen-share-classes, worked examples H4, H5, E14–E21)
class AddClassExpensesPayableToFundNavs < ActiveRecord::Migration[8.1]
  def change
    add_column :fund_navs, :class_expenses_payable_cents, :decimal, precision: 20, scale: 2, default: 0, null: false
  end
end
