class AddRootFolderToEntity < ActiveRecord::Migration[8.0]
  def change
    add_reference :entities, :root_folder, null: true, foreign_key: { to_table: :folders }

    Entity.all.each do |entity|      
      folder = entity.folders.where(level: 0).first
      entity.update(root_folder_id: folder&.id)
    end

    # Ensure non null root_folder
    # change_column_null :entities, :root_folder_id, false
  end
end
