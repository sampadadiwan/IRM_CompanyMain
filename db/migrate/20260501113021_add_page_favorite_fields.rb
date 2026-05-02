class AddPageFavoriteFields < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:favorites, :user_id)
      add_reference :favorites, :user, foreign_key: true, index: true
    end
    unless column_exists?(:favorites, :title)
      add_column :favorites, :title, :string
    end
    unless column_exists?(:favorites, :url)
      add_column :favorites, :url, :string
    end
  end
end
