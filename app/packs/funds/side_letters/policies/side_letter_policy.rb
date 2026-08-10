# Side letters are GP-internal legal records: entity-scoped, admin-managed.
class SideLetterPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      # Feature is dark for tenants that have not switched the agent on.
      return scope.none unless user.entity&.support_agents&.set?(:side_letter_obligation_agent)

      if user.has_cached_role?(:company_admin) || user.has_cached_role?(:employee) || user.support?
        scope.where(entity_id: user.entity_id)
      else
        scope.none
      end
    end
  end

  def index?
    agent_enabled? &&
      (user.has_cached_role?(:company_admin) || user.has_cached_role?(:employee) || user.support?)
  end

  def show?
    index? && belongs_to_entity?(user, record)
  end

  def create?
    agent_enabled? && user.has_cached_role?(:company_admin) && belongs_to_entity?(user, record)
  end

  def new?
    agent_enabled? && user.has_cached_role?(:company_admin)
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    create?
  end

  private

  # The whole side letter obligation feature hangs off the agent entity flag —
  # with the agent off there is nothing to extract, review or enforce.
  def agent_enabled?
    user.entity&.support_agents&.set?(:side_letter_obligation_agent)
  end
end
