class AgentBaseService < Trailblazer::Operation
  def initialize_agent(ctx, **)
    ctx[:support_agent] = SupportAgent.find(ctx[:support_agent_id])
    model = ctx[:llm] || ENV["SUPPORT_AGENT_MODEL"] || "gpt-5"
    ctx[:llm] = RubyLLM.chat(model: model)
  end
end
