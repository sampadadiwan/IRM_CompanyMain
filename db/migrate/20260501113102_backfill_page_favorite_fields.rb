class BackfillPageFavoriteFields < ActiveRecord::Migration[8.1]
  def up
    if column_exists?(:favorites, :favoritable_type)
      Favorite.reset_column_information

      Favorite.find_each do |favorite|
        next unless favorite.favoritor_type == "User"

        favorite.update_columns(
          user_id: favorite.favoritor_id,
          title: legacy_favorite_title(favorite),
          url: legacy_favorite_url(favorite)
        )
      end
    end
  end

  def down
    # no-op
  end

  private


  def legacy_favorite_title(favorite)
    obj = favorite.favoritable_type.constantize.find_by(id: favorite.favoritable_id)
    if obj.present?
      obj.to_s
    else
      favorite.favoritable_type + " #" + favorite.favoritable_id.to_s
    end
  end

  def legacy_favorite_url(favorite)
    "/" + favorite.favoritable_type.underscore.pluralize + "/" + favorite.favoritable_id.to_s
  end
end
