class GridViewPreference < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :custom_grid_view, optional: true
  acts_as_list column: :sequence, scope: :owner
  validates :key, presence: true
end
