class AddUniqeIdxForNameInFcf < ActiveRecord::Migration[7.1]
  def up
    add_index :form_custom_fields, [:name, :form_type_id], unique: true
  end

  def down
    remove_index :form_custom_fields, [:name, :form_type_id]
  end
end
