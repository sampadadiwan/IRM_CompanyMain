class ExchangeRatePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record)
  end

  # A fund-specific rate also needs update access on that fund (H21)
  def create?
    return false unless belongs_to_entity?(user, record)
    return true if record.owner_id.blank?

    fund = Fund.find_by(id: record.owner_id, entity_id: record.entity_id)
    fund.present? && FundPolicy.new(user, fund).update?
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    true
  end

  def generate_tracking_numbers?
    belongs_to_entity?(user, record) && record.latest?
  end
end
