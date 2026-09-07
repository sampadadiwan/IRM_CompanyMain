# Membership of one AllocationRunTemplate in one AllocationRunTemplateGroup, with the
# numeric position that decides run order (decision 18: numeric position, as Ratio
# Templates use, rather than drag and drop).
class AllocationRunTemplateGroupItem < ApplicationRecord
  belongs_to :allocation_run_template_group, inverse_of: :items
  belongs_to :allocation_run_template, inverse_of: :group_items

  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :allocation_run_template_id, uniqueness: { scope: :allocation_run_template_group_id,
                                                       message: "is already in this group" }

  delegate :fund, :name, to: :allocation_run_template
end
