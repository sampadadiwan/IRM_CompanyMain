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
    user.entity_id == record.entity_id || user.entity_id == record.investor.investor_entity_id || super_user?
  end

  def create?
    user.entity_id == record.entity_id
  end

  def request_access?
    user.entity_id == record.investor.investor_entity_id && !record.approved
  end

  def new?
    create?
  end

  def update?
    user.entity_id == record.entity_id || super_user?
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
