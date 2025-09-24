class SupportAgent < ApplicationRecord
  include WithCustomField
  include WithFolder

  AGENT_TYPES = ["KycOnboardingAgent"].freeze

  belongs_to :entity

  validates :name, presence: true
  validates :name, length: { maximum: 30 }
  validates :agent_type, presence: true
  validates :agent_type, length: { maximum: 20 }

  def to_s
    name
  end
end
