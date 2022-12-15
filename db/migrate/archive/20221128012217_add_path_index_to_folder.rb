class AddPathIndexToFolder < ActiveRecord::Migration[7.0]
  def change
    change_column :folders, :full_path, :string, index: true
  end
end
