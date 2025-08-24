class AddRegEnvToFormCustomFields < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:form_custom_fields, :reg_env)
      add_column :form_custom_fields, :reg_env, :string
    end
  end
end
