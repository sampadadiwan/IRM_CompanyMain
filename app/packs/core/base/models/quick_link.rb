class QuickLink < ApplicationRecord
  belongs_to :entity, optional: true
  has_many :quick_link_steps, -> { order(position: :asc) }, inverse_of: :quick_link, dependent: :destroy
  accepts_nested_attributes_for :quick_link_steps, reject_if: :all_blank, allow_destroy: true
end
