class ChangeRegEnvLengthTo15 < ActiveRecord::Migration[8.0]
  def change
    change_column :form_custom_fields, :reg_env, :string, limit: 15
  end
end
