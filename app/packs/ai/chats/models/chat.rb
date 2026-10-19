class Chat < ApplicationRecord
  # Includes methods like ask, with_tool, with_instructions, etc.
  # Automatically persists associated messages and tool calls.
  acts_as_chat

  attr_accessor :enable_broadcast

  belongs_to :user
  belongs_to :owner, polymorphic: true
  attr_readonly :owner_id, :owner_type # never moves to another owner (funds_api_security_policy_plan.md, B)
  belongs_to :entity
  validates :name, presence: true
  validates :assistant_type, length: { maximum: 50 }, allow_blank: true

  def model_id
    super || @model_string
  end

  before_validation :set_model

  def set_model
    return if model_id.blank?
    return if model.present? && !model_id_changed?

    self.model = Model.where(model_id: model_id).last
  end

  def should_broadcast?
    enable_broadcast
  end
end
