# Ledger entries a class names as its own expenses and their payments, charged to that class only
# (evergreen-share-classes, worked examples H4–H6, X1–X5)
class AddClassExpenseEntriesToEvergreenClassTerms < ActiveRecord::Migration[8.1]
  def change
    add_column :evergreen_class_terms, :class_expense_entry_name, :string, limit: 125
    add_column :evergreen_class_terms, :class_expense_paid_entry_name, :string, limit: 125
  end
end
