class Chat < ApplicationRecord
  # Includes methods like ask, with_tool, with_instructions, etc.
  # Automatically persists associated messages and tool calls.
  acts_as_chat # Assumes Message and ToolCall model names

  belongs_to :user
  belongs_to :owner, polymorphic: true
  belongs_to :entity
  validates :model_id, :name, presence: true

  broadcasts_to ->(chat) { [chat, "messages"] }
end
