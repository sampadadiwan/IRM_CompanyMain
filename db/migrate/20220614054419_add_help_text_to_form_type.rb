class AddHelpTextToFormType < ActiveRecord::Migration[7.0]
  def change
    add_column :form_custom_fields, :help_text, :text
  end
end
