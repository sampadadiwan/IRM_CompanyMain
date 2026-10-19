class NotePolicy < ApplicationPolicy
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
    user.enable_investors
  end

  def show?
    user.enable_investors &&
      belongs_to_entity?(user, record) && (user.has_cached_role?(:company_admin) || (user.id == record.user_id) || (record.owner && owner_policy.show?) || support?)
  end

  def create?
    # D: the parent is in one of the user's firms (funds_api_security_policy_plan.md)
    belongs_to_entity?(user, record) && parent_in_users_firms?(record.owner) && (user.has_cached_role?(:company_admin) || (record.owner && owner_policy.create?) || (user.id == record.user_id) || support?)
  end

  # Adding a new policy to check only for notes that are added via Deal Notes Tab
  def deal_note_create?
    belongs_to_entity?(user, record) && (user.has_cached_role?(:company_admin) || (record.owner && owner_policy.create?) || support?)
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
    update? || (user.id == record.user_id && record.owner && owner_policy.show?)
  end
end
