class AddUniqeIdxForNameInFcf < ActiveRecord::Migration[7.1]
  def up
    # Ensure existing data is migrated, remove dups
    FormCustomField.all.each do |fcf|
      unless fcf.save
        # This means there is prob already a duplicate
        old_name = fcf.name
        fcf.name += rand(1000).to_s
        fcf.save
        # This goes in and changes the actual json_fields in the models
        fcf.change_name(old_name)
      end
    end

    add_index :form_custom_fields, [:name, :form_type_id], unique: true
  end

  def down
    remove_index :form_custom_fields, [:name, :form_type_id]
  end
end
