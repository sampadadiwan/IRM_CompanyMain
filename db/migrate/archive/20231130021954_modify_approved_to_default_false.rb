class ModifyApprovedToDefaultFalse < ActiveRecord::Migration[7.1]
  def change
    change_column_default :documents, :approved, false 
  end
end
