class AddUniqeIdxForNameInFcf < ActiveRecord::Migration[7.1]
  def up
    # Ensure existing data is migrated, remove dups
    FormCustomField.all.each do |fcf|
      unless fcf.save
        fcf.name += rand(1000).to_s
        fcf.save
      end
    end

    add_index :form_custom_fields, [:name, :form_type_id], unique: true
  end

  def down
    remove_index :form_custom_fields, [:name, :form_type_id]
  end
end
