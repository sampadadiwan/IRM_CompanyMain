class InvestorNoticeItemPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      # Items belong to the GP entity that authored the parent notice
      # (InvestorNoticeItem#set_entity_id copies it from investor_notice.entity_id).
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.has_cached_role?(:company_admin)
  end

  def show?
    belongs_to_entity?(user, record)
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
