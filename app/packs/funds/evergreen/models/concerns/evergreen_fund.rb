# Evergreen associations and helpers on Fund. Purely additive: a fund without an
# EvergreenFundSetting (every closed-ended fund) answers evergreen? => false and nothing else changes.
# Backward compatibility B1 — openspec/changes/open-ended-funds/design.md#backward-compatibility
module EvergreenFund
  extend ActiveSupport::Concern

  included do
    # Destroy order matters: fills before orders / NAVs, orders before dealing dates
    # (FundNav and DealingDate restrict_with_error on their children)
    # Send-once log rows go with the fund (FK), even after it was switched back to closed-ended
    has_many :evergreen_notification_logs, dependent: :delete_all
    has_many :dealing_fills, dependent: :destroy
    has_many :dealing_orders, dependent: :destroy
    has_many :dealing_dates, dependent: :destroy
    has_many :fund_navs, dependent: :destroy
    has_many :evergreen_class_terms, dependent: :destroy
    has_one :evergreen_fund_setting, dependent: :destroy
  end

  # True only when the entity has evergreen funds switched on AND this fund has evergreen settings.
  # Turning the entity switch off reverts every screen to closed-ended (rollback path).
  # Worked examples E1, E47
  def evergreen?
    return @evergreen if defined?(@evergreen)

    @evergreen = entity&.permissions&.enable_evergreen_funds? && evergreen_fund_setting.present?
  end

  def reset_evergreen_cache
    remove_instance_variable(:@evergreen) if defined?(@evergreen)
  end

  # The approved NAV per unit (major units) for a class on or before a date; used by the
  # "Management Fee on NAV" fund formula. nil when no approved NAV exists yet.
  # Worked example H27
  def evergreen_nav_per_unit(unit_type, date)
    cents = evergreen_nav_per_unit_cents(unit_type, date)
    cents && (cents / 100)
  end

  # The same in cents, for formulas (account entry amounts are cents)
  def evergreen_nav_per_unit_cents(unit_type, date)
    FundNav.latest_approved(self, unit_type, date)&.nav_per_unit_cents&.to_d
  end
end
