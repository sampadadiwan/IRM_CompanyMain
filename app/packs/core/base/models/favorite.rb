class Favorite < ApplicationRecord
  extend ActsAsFavoritor::FavoriteScopes

  belongs_to :favoritable, polymorphic: true
  belongs_to :favoritor, polymorphic: true, touch: true

  validates :favoritable_id, uniqueness: { scope: %i[favoritable_type favoritor_type favoritor_id] }
end
