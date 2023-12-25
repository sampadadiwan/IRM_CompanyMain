class AddStepToFormCustomField < ActiveRecord::Migration[7.1]
  def change
    add_column :form_custom_fields, :step, :integer, default: 100 # Default is last step always
  end
end
