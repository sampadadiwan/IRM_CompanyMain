# Entity Market Data settings: visible to the entity's users, edited by its company admin or
# CapHive support (same rule as EntityPolicy#update?). Only for entities with a market-data feature.
# openspec/changes/fund-market-data — design card ① access table (H2, X1).
class MarketDataSettingPolicy < ApplicationPolicy
  def show?
    market_data_entity? && belongs_to_entity?(user, record)
  end

  def update?
    show? && (user.has_cached_role?(:company_admin) || user.support?) && !user.investor_advisor?
  end

  def test_feed?
    update?
  end

  private

  def market_data_entity?
    perms = record.entity.permissions
    perms.enable_market_rates? || perms.enable_market_prices? || perms.enable_derivatives?
  end
end
