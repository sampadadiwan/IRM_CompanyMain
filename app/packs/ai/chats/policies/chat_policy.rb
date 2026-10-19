class ChatPolicy < ApplicationPolicy
  class Scope < BaseScope
    def resolve
      if user.has_cached_role?(:company_admin)
        scope.where(entity_id: user.entity_id)
      else
        scope.where(user_id: user.id)
      end
    end
  end

  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record)
  end

  def create?
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    belongs_to_entity?(user, record) && parent_in_users_firms?(record.owner) && user.has_cached_role?(:company_admin)
  end

  def new?
    create?
  end

  def send_message?
    update?
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
end
