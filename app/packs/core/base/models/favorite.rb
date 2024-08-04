class Favorite < ApplicationRecord
  extend ActsAsFavoritor::FavoriteScopes

  belongs_to :favoritable, polymorphic: true
  # This is typically a User model, we touch it to bust the topbar chache which caches the favs
  belongs_to :favoritor, polymorphic: true, touch: true

  validates :favoritable_id, uniqueness: { scope: %i[favoritable_type favoritor_type favoritor_id] }
end
