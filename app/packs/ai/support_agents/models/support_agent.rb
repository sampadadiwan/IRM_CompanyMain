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

  AGENT_TYPES = %w[KycOnboardingAgent KycDocExtractorAgent PortfolioCompanyAgent FundStatsAgent PortfolioReportAgent CallNoticeAgent CashFlowAssistantAgent DistributionReadinessAgent EsignMonitorAgent DataQualityAgent LpAssistantAgent PortfolioAssistantAgent PortfolioScoringAgent NoteSummarizerAgent DealsReportAgent PresentationAnalystAgent CustomerSupportAgent RtaReconciliationAgent DealManagementAgent SideLetterObligationAgent TemplateFixAgent RemittanceReconciliationAgent CpCsExtractionAgent].freeze
  CATEGORIES = %w[Ops Finance Portfolio Onboarding Other].freeze

  belongs_to :entity
  has_one :agent_schedule, dependent: :destroy

  # Matches the fallback used by db/migrate/archive/20260514100003_backfill_llm_model_for_support_agents.rb
  attribute :llm_model, :string, default: "gemini-3.7-flash"

  scope :enabled, -> { where(enabled: true) }
  scope :for_user, lambda { |user|
    joins(entity: :entity_setting).where(
      entity_id: Investor.where(investor_entity_id: user.entity_id).pluck(:entity_id) + [user.entity_id]
    ).where(
      "(entity_settings.openai_api_key IS NOT NULL AND entity_settings.openai_api_key != '') OR (entity_settings.gemini_api_key IS NOT NULL AND entity_settings.gemini_api_key != '') OR (entity_settings.anthropic_api_key IS NOT NULL AND entity_settings.anthropic_api_key != '') OR (entity_settings.openrouter_api_key IS NOT NULL AND entity_settings.openrouter_api_key != '')"
    )
  }

  private

  # Override WithCustomField's generic fallback which uses `.last` and picks the wrong form type.
  # Always resolve by the agent_type tag so each agent type gets its own isolated custom fields.
  def setup_form_type
    return if form_type_id.present?
    return unless agent_type.present? && entity.present?

    self.form_type = entity.form_types
                           .where(name: "SupportAgent", tag: agent_type)
                           .first_or_create!(name: "SupportAgent", tag: agent_type)
  end

  public

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
    when "DealsReportAgent"
      ["Show fill rate across deals", "Which deals need attention?", "List top investors by amount"]
    when "PortfolioReportAgent"
      ["Top 5 portfolio companies by valuation", "Which companies missed KPIs?"]
    when "PortfolioCompanyAgent"
      ["Show latest KPIs", "What's the current valuation?", "List recent investments"]
    when "PortfolioAssistantAgent"
      ["Show recent valuations", "Plot KPIs over time", "Summarize portfolio performance"]
    when "PortfolioScoringAgent"
      ["What is the overall score?", "Show scoring dimensions", "What are the key risks?"]
    when "NoteSummarizerAgent"
      ["Summarize last quarter's notes", "What are the action items?", "Show all meeting notes"]
    when "CustomerSupportAgent"
      ["How do I create a capital call?", "What's the process for investor onboarding?", "How do I generate a distribution notice?"]
    when "PresentationAnalystAgent"
      # PRD §7 — sample questions surfaced in the chat panel welcome state.
      # Each question is designed to show the GP what kinds of patterns the agent can find.
      [
        "What commitments from earlier periods were not followed up on?",
        "Which risks disappeared without a stated resolution?",
        "Compare the ARR targets stated across all periods.",
        "What happened to the [initiative name] — when did it last appear?"
      ]
    when "RtaReconciliationAgent"
      [
        "Are all folios matched?",
        "Which folios have breaks?",
        "Are there any pending requests?",
        "Show the last reconciliation summary."
      ]
    when "CpCsExtractionAgent"
      [
        "What obligations were extracted from this investment?",
        "Show me all conditions precedent pending review",
        "Which investments have overdue obligations?"
      ]

    else
      []
    end
  end

  # Returns true when the entity's support_agents bitflag for this agent is set.
  # Used by the show page to disable the Run Now button for unlicensed agents.
  # Defaults to true for unknown agent types so the UI remains usable.
  def entity_flag_enabled?
    flag = SupportAgentsSetupService.flag_for(agent_type)
    entity.support_agents.set?(flag)
  rescue StandardError
    true
  end

  # Required by WithFolder so Document#setup_folder can resolve a folder for attached skill files.
  def folder_path
    "Support Agents/#{agent_type}"
  end

  # Finds the skill document for the given sector by inspecting File-type custom fields
  # whose meta_data marks them as skills (e.g. "skill: true, sector: D2C").
  # Falls back to a "General" skill if no sector-specific one is configured.
  # Returns the matching Document record, or nil if no skill is configured at all.
  def skill_for_sector(sector)
    skill_fields = form_custom_fields.select(&:skill_tagged?)

    # Prefer exact sector match, then fall back to General
    fcf = skill_fields.find { |f| f.meta_data.to_s.match?(/sector[:\s=]+#{Regexp.escape(sector.to_s)}/i) } ||
          skill_fields.find { |f| f.meta_data.to_s.match?(/sector[:\s=]+General/i) }
    return nil unless fcf

    documents.find_by(name: fcf.human_label)
  end
end
