# Audit-trail row: one fulfillment of an obligation — who did it, when, how,
# with optional documentary evidence. Created automatically when a projected
# task is completed (SideLetterObligation#register_task_completion) or manually
# for out-of-band fulfillments. Feeds the Compliance Evidence Binder.
class ObligationFulfillment < ApplicationRecord
  belongs_to :entity
  belongs_to :side_letter_obligation
  belongs_to :fulfilled_by, class_name: "User", optional: true
  belongs_to :document, optional: true
  belongs_to :task, optional: true

  validates :fulfilled_at, presence: true
  # The "how" is the audit substance — evidence doc is optional, method is not
  validates :fulfillment_method, presence: true

  def self.ransackable_attributes(_auth_object = nil)
    %w[fulfilled_at period_covered]
  end

  # No association is searchable; Ransack 6 asks for this list on any non-column condition and raises without it
  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
