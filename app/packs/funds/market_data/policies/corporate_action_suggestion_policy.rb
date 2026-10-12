# Corporate action suggestions: visible to the entity's portfolio users, confirmed or dismissed by
# its company admin, CapHive support or employees with update rights. fund-market-data, card ②.
class CorporateActionSuggestionPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    user.entity.permissions.enable_market_prices?
  end

  def confirm?
    belongs_to_entity?(user, record) && (user.support? || company_admin_or_emp_crud?(user, record, "update"))
  end

  def dismiss?
    confirm?
  end
end
