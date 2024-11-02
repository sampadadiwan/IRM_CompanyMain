class ComplianceRule < ApplicationRecord
  belongs_to :entity

  scope :for_class, ->(klass) { where(for_class: klass) }
  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :for_schedule, ->(schedule) { where(schedule:) }

  validates :for_class, presence: true
  validates :rule, presence: true
  validates :for_class, length: { maximum: 20 }
  validates :schedule, length: { maximum: 40 }

  def to_s
    "#{for_class} - #{rule&.truncate(50)}"
  end
end
