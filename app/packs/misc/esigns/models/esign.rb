class Esign < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  belongs_to :document, optional: true
  belongs_to :owner, polymorphic: true
  acts_as_list scope: :owner, column: :sequence_no

  scope :not_completed, -> { where(completed: false) }
  scope :completed, -> { where(completed: true) }
  scope :for_signature_type, ->(signature_type) { where(signature_type: signature_type.to_s) }
  scope :for_adhaar, -> { where(signature_type: "adhaar") }
  scope :for_dsc, -> { where(signature_type: "dsc") }
end
