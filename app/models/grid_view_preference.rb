class GridViewPreference < ApplicationRecord
  belongs_to :custom_grid_view
  acts_as_list column: :sequence, scope: :custom_grid_view
  validates :key, presence: true
end
