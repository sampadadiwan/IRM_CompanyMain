class AddFormTypeToAllocation < ActiveRecord::Migration[7.2]
  def change
    add_reference :allocations, :form_type, null: true, foreign_key: true
  end
end
