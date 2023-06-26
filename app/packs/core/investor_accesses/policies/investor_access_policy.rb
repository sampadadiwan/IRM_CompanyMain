class InvestorAccessPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) || user.entity_id == record.investor.investor_entity_id || super_user?
  end

  def create?
    belongs_to_entity?(user, record)
  end

  def request_access?
    user.entity_id == record.investor.investor_entity_id && !record.approved
  end

  def new?
    create?
  end

  def update?
    belongs_to_entity?(user, record) || super_user?
  end

  def approve?
    update?
  end

  def edit?
    update?
  end

  def destroy?
    create? || super_user?
  end

  def notify_kyc_required?
    update? && record.approved && record.entity.enable_kycs
  end
end
