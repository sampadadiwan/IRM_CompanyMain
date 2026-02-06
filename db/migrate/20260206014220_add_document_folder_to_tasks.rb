class AddDocumentFolderToTasks < ActiveRecord::Migration[8.1]
  def change
    # Clean up any invalid data that might be causing FK failure
    # Using execute to bypass model logic and ensure it runs during migration
    if column_exists?(:tasks, :document_folder_id)
      say_with_time "Cleaning invalid document_folder_id values on tasks" do
        execute "UPDATE tasks SET document_folder_id = NULL WHERE document_folder_id NOT IN (SELECT id FROM folders)"
      end
      change_column_null :tasks, :document_folder_id, true
    end

    unless column_exists?(:tasks, :document_folder_id)
      add_foreign_key :tasks, :folders, column: :document_folder_id unless foreign_key_exists?(:tasks, :folders, column: :document_folder_id)
    else
      add_foreign_key :tasks, :folders, column: :document_folder_id unless foreign_key_exists?(:tasks, column: :document_folder_id)
      add_index :tasks, :document_folder_id unless index_exists?(:tasks, :document_folder_id)
    end
  end
end
