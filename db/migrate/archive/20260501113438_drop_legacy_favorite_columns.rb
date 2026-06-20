class DropLegacyFavoriteColumns < ActiveRecord::Migration[8.1]
  def change
    remove_index :favorites, name: "index_favorites_on_blocked", if_exists: true
    remove_index :favorites, name: "fk_favoritables", if_exists: true
    remove_index :favorites, name: "uniq_favs_and_favoritables", if_exists: true
    remove_index :favorites, name: "index_favorites_on_favoritable", if_exists: true
    remove_index :favorites, name: "fk_favorites", if_exists: true
    remove_index :favorites, name: "index_favorites_on_favoritor", if_exists: true
    remove_index :favorites, name: "index_favorites_on_scope", if_exists: true

    remove_column :favorites, :favoritable_type, :string if column_exists?(:favorites, :favoritable_type)
    remove_column :favorites, :favoritable_id, :bigint if column_exists?(:favorites, :favoritable_id)
    remove_column :favorites, :favoritor_type, :string if column_exists?(:favorites, :favoritor_type)
    remove_column :favorites, :favoritor_id, :bigint if column_exists?(:favorites, :favoritor_id)
    remove_column :favorites, :scope, :string if column_exists?(:favorites, :scope)
    remove_column :favorites, :blocked, :boolean if column_exists?(:favorites, :blocked)

    change_column_null :favorites, :user_id, false
    change_column_null :favorites, :title, false
    change_column_null :favorites, :url, false

    add_index :favorites, [:user_id, :url],
      unique: true,
      name: "index_favorites_on_user_id_and_url",
      if_not_exists: true
  end
end
