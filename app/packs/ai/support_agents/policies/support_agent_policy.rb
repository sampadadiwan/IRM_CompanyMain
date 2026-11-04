# frozen_string_literal: true

# Pundit policy for SupportAgent records.
#
# Authorizes two distinct audiences:
#   1. Fund-manager staff — read/write access to their own entity's agents
#      (gated by `belongs_to_entity?` + `:company_admin` role for writes).
#   2. Limited Partners — read-only access to an enabled LpAssistantAgent
#      belonging to any fund whose entity has granted the LP an approved
#      InvestorAccess. LPs never get write/run/destroy.
#
# @see ApplicationPolicy
# @see SupportAgent
# @see InvestorAccess
class SupportAgentPolicy < ApplicationPolicy
  class Scope < BaseScope
    def resolve
      if user.has_cached_role?(:company_admin)
        # The Support Console's record lives on the CapHive entity but is driven only from
        # /support_console, so it is kept out of that entity's AI Agents list.
        scope.where(entity_id: user.entity_id).where("support_agents.agent_type IS NULL OR support_agents.agent_type <> ?", "SupportConsoleAgent")
      else
        scope.none
      end
    end
  end

  def index?
    true
  end

  def show?
    # X30, X31 — the Support Console's agent sits on the CapHive entity, so every CapHive user would
    # pass belongs_to_entity?. It is driven only from /support_console under SupportConsolePolicy;
    # the generic chat routes (and everything else gated on show?) must not reach it.
    return false if record.agent_type == SupportConsoleAgent::AGENT_TYPE

    belongs_to_entity?(user, record) || lp_assistant_access?
  end

  def create?
    belongs_to_entity?(user, record) && user.has_cached_role?(:company_admin)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def setup?
    user.has_cached_role?(:company_admin) || support?
  end

  def llm_keys?
    setup?
  end

  def update_llm_keys?
    setup?
  end

  def run?
    # The agent itself: own firm, company admin
    return false unless update?

    # N8-1 — the record the request names (SupportAgent#run_target, set by support_agents#run /
    # #run_with_steps) must be in one of the user's firms. No target: the agent runs over its own
    # firm's targets (batch, scheduled), nothing more to check (N8-H).
    target = record.run_target
    return true if target.nil?

    # The target must be in the agent's own firm - the same rule SupportAgentJob enforces - so a
    # group-company admin can't create a pending report on a child firm's record that the job refuses
    target_firm = SupportAgent.firm_id_of(target)
    target_firm == record.entity_id && users_firm?(user, target_firm)
  end

  def run_with_steps?
    # Same target check as run? (N8-1)
    run?
  end

  def run_batch?
    run?
  end

  def cancel?
    run?
  end

  def status?
    show?
  end

  def step_details?
    show?
  end

  def update_score?
    show?
  end

  def update_note_summary?
    show?
  end

  def executions?
    show?
  end

  def execution?
    show?
  end

  private

  # @return [Boolean] true when record is an enabled LpAssistantAgent and
  #   the current user has an approved InvestorAccess to its entity.

  def lp_assistant_access?
    return false unless record.agent_type == "LpAssistantAgent"
    return false unless record.enabled

    InvestorAccess.exists?(
      entity_id: record.entity_id,
      user_id: user.id,
      approved: true
    )
  end
end
