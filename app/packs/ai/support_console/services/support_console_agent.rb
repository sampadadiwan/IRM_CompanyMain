# frozen_string_literal: true

# The Support Console's SupportAgent type.
#
# Support Console conversations are stored as AgentChatSession / AgentChatMessage rows, and
# agent_chat_sessions.support_agent_id is NOT NULL, so every conversation is owned by one
# SupportAgent of this type on the CapHive entity (CAPHIVE_ENTITY_ID). Nothing runs in this
# process: each question is answered by Claude Code on the support machine, driven by
# SupportConsoleTurnJob. This class exists so SupportAgent#agent (agent_type.constantize)
# resolves, and to find or create that single record.
#
# @see SupportConsoleTurnJob
# @see openspec/changes/support-console/design.md (Design decision 1)
class SupportConsoleAgent
  AGENT_TYPE = "SupportConsoleAgent"
  NAME = "Support Console"

  # The CapHive-owned SupportAgent, if it exists yet. For GET requests, which run on a
  # read-only connection and so cannot create it.
  #
  # @return [SupportAgent, nil]
  def self.existing
    SupportAgent.find_by(entity_id: ENV.fetch("CAPHIVE_ENTITY_ID"), agent_type: AGENT_TYPE)
  end

  # Finds or creates the CapHive-owned SupportAgent that owns every console conversation.
  # Called when the first question is asked (a POST), never from a GET.
  #
  # @return [SupportAgent]
  # @raise [KeyError] when CAPHIVE_ENTITY_ID is not configured
  def self.record
    # One row per environment, keyed by the CapHive entity and the type.
    SupportAgent.find_or_create_by!(entity_id: ENV.fetch("CAPHIVE_ENTITY_ID"), agent_type: AGENT_TYPE) do |agent|
      agent.name = NAME
      agent.enabled = true
      agent.description = "Answers support questions with Claude Code on the support machine"
    end
  end

  # Support agent runs (SupportAgentJob) never apply: the console answers per question.
  #
  # @return [Array] no targets
  def targets(_id = nil)
    []
  end

  # @return [Array] no configurable steps
  def self.step_definitions
    []
  end
end
