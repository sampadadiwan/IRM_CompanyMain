class MakeFormTypeTagDefault < ActiveRecord::Migration[8.0]
  def change
    # Add tag column with default value "Default"
    change_column_default :form_types, :tag, from: nil, to: "Default"
    # Set existing records with null tag to "Default"
    FormType.where(tag: [nil, ""]).update_all(tag: "Default")
    # Change null true to false for existing records
    change_column_null :form_types, :tag, false
  end
end
