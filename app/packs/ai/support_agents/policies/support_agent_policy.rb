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
        scope.where(entity_id: user.entity_id)
      else
        scope.none
      end
    end
  end

  def index?
    true
  end

  def show?
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

  def run?
    update?
  end

  def run_with_steps?
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
