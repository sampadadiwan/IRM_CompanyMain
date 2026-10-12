# Derivatives are available only when the entity has the Derivatives feature, the fund has it
# switched on, and the user can see (read) or update (record) the fund. Other entities never.
# Worked examples X16–X18, X25 — openspec/changes/fund-market-data/business-rules.md
class DerivativeContractPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    feature_on? && FundPolicy.new(user, fund).show?
  end

  def show?
    belongs_to_entity?(user, record) && index?
  end

  def create?
    belongs_to_entity?(user, record) && feature_on? && FundPolicy.new(user, fund).update?
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

  def record_event?
    update?
  end

  private

  def fund
    record.is_a?(DerivativeContract) ? record.fund : record
  end

  def feature_on?
    fund.present? && fund.entity.permissions.enable_derivatives? && fund.features.enable_derivatives?
  end
end
