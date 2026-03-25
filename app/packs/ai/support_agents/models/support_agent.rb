class SupportAgent < ApplicationRecord
  # SupportAgent represents an AI-driven entity responsible for
  # validating consistency between structured fields on a model
  # and extracted values from uploaded documents. It leverages LLMs
  # (Large Language Models) to parse and extract content for verification.
  #
  # Includes:
  #   - WithCustomField: adds support for attaching custom metadata/fields
  #   - WithFolder: provides organization of agents into folders
  #
  # Validations enforce constraints on agent identity and type to ensure
  # consistent naming and classification.
  include WithCustomField
  include WithFolder
  include SupportAgentHelper

  AGENT_TYPES = %w[KycOnboardingAgent PortfolioCompanyAgent FundStatsAgent PortfolioReportAgent CallNoticeAgent CashFlowAssistantAgent].freeze

  belongs_to :entity
  has_one :agent_schedule, dependent: :destroy

  scope :enabled, -> { where(enabled: true) }

  validates :name, presence: true
  validates :name, length: { maximum: 30 }
  validates :agent_type, presence: true
  validates :agent_type, length: { maximum: 30 }

  # Returns the human-readable representation of the SupportAgent
  # In this case, simply the name string.
  #
  # @return [String] the name of the agent
  def to_s
    name
  end

  def agent
    agent_type.constantize
  end

  # --- Generic Chat Config ---
  def chat_config
    (json_fields || {}).fetch("chat_config", {})
  end

  def chat_enabled?
    [true, "true"].include?(chat_config["enabled"])
  end

  def chat_model
    chat_config["model"] || entity&.entity_setting&.default_llm_model || ENV.fetch('DEFAULT_MODEL', 'gpt-4o-mini')
  end
end
