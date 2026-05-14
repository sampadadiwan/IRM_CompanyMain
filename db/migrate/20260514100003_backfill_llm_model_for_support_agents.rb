class BackfillLlmModelForSupportAgents < ActiveRecord::Migration[8.0]
  # Priority: Gemini 3.1 Pro → Claude Sonnet 4.6 → GPT-5.5
  PREFERRED_MODELS = [
    { key: :gemini_api_key,    model: "gemini-3.1-pro-preview" },
    { key: :anthropic_api_key, model: "claude-sonnet-4-6" },
    { key: :openai_api_key,    model: "gpt-5.5" }
  ].freeze

  DEFAULT_FALLBACK = "gemini-3-flash-preview"

  def up
    SupportAgent.includes(entity: :entity_setting).where(llm_model: nil).each do |agent|
      setting = agent.entity.entity_setting
      chosen = PREFERRED_MODELS.find { |p| setting&.send(p[:key]).present? }
      agent.update_columns(llm_model: chosen ? chosen[:model] : DEFAULT_FALLBACK)
    end
  end

  def down
    # intentionally a no-op: reverting to nil is trivial if needed
  end
end
