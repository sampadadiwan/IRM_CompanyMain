class OptionPoolPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) || user.holdings.where(entity_id: record.entity_id).present? || super_user?
  end

  def create?
    belongs_to_entity?(user, record)
  end

  def new?
    create?
  end

  def update?
    (create? || super_user?) && !record.approved
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def approve?
    update? && user.has_cached_role?(:approver)
  end

  def run_vesting?
    belongs_to_entity?(user, record)
  end

  def approve_all_holdings?
    create? && user.has_cached_role?(:approver)
  end
end
