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

  # Model lookup is RubyLLM's job in 2.x: `chat.model = "gemini-..."` (or `model_id:`)
  # is resolved to a RubyLLM::ActiveRecord::Model row by acts_as_chat's before_save.

  def should_broadcast?
    enable_broadcast
  end
end
