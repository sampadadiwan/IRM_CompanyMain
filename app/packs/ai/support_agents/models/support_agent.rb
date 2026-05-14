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

  AGENT_TYPES = %w[KycOnboardingAgent PortfolioCompanyAgent FundStatsAgent PortfolioReportAgent CallNoticeAgent CashFlowAssistantAgent DistributionReadinessAgent EsignMonitorAgent DataQualityAgent LpAssistantAgent PortfolioAssistantAgent].freeze

  belongs_to :entity
  has_one :agent_schedule, dependent: :destroy

  scope :enabled, -> { where(enabled: true) }

  validates :name, presence: true
  validates :name, length: { maximum: 30 }
  validates :agent_type, presence: true
  validates :agent_type, length: { maximum: 30 }
  validates :llm_model, presence: true

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

  # Resolves the model to use for this agent: per-agent setting → entity default → env fallback.
  def effective_model
    llm_model.presence ||
      entity&.entity_setting&.default_llm_model.presence ||
      ENV.fetch('DEFAULT_MODEL', nil)
  end

  def chat_model
    effective_model
  end

  # Returns the list of starter questions surfaced as clickable chips in the
  # chat panel's welcome state. Each agent type provides its own set so the
  # generic chat UI can teach users what they can ask without per-host wiring.
  #
  # @return [Array<String>] sample questions for this agent's `agent_type`.
  #   Returns an empty array for agent types without curated examples.
  # @see #chat_enabled?
  # @see AGENT_TYPES
  def sample_questions
    case agent_type
    when "LpAssistantAgent"
      ["What's my current IRR?", "Show my SOA", "When is the next capital call?"]
    when "CashFlowAssistantAgent"
      ["Which funds are running low?", "Show stale balances", "Recommend capital calls"]
    when "PortfolioReportAgent"
      ["Top 5 portfolio companies by valuation", "Which companies missed KPIs?"]
    when "PortfolioCompanyAgent"
      ["Show latest KPIs", "What's the current valuation?", "List recent investments"]
    when "PortfolioAssistantAgent"
      ["Show recent valuations", "Plot KPIs over time", "Summarize portfolio performance"]
    else
      []
    end
  end
end
