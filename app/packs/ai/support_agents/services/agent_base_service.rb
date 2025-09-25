class AgentBaseService < Trailblazer::Operation
  def initialize_agent(ctx, **)
    @support_agent = SupportAgent.find(ctx[:support_agent_id])
    ctx[:support_agent] = @support_agent
    model = ctx[:llm] || ENV["SUPPORT_AGENT_MODEL"] || "gemini-2.5-flash" # || "gpt-5"
    ctx[:llm] = RubyLLM.chat(model: model)
  end

  def enabled?(field)
    %w[true 1 enabled yes].include? @support_agent.json_fields[field]&.downcase
  end
end
