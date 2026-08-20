class InvestorNoticeEntryPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    # Match InvestorNoticePolicy#index? — the Scope already restricts rows to
    # the user's entity, but an LP has no business browsing the entries index.
    user.has_cached_role?(:company_admin)
  end

  def show?
    belongs_to_entity?(user, record) || user.entity_id == record.investor_entity_id
  end

  def create?
    belongs_to_entity?(user, record)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    create?
  end

  def destroy?
    create?
  end
end
