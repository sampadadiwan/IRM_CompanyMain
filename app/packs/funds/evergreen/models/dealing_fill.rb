# What one order got on one dealing date, frozen at confirm: units, value, NAV used, what the gate
# carried forward, and links to the settlement row and the FundUnit that moved.
# Worked examples H21, H24, H25, E32 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingFill < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  belongs_to :dealing_date
  belongs_to :dealing_order
  belongs_to :fund_nav, optional: true
  belongs_to :capital_remittance, optional: true
  belongs_to :capital_distribution_payment, optional: true
  belongs_to :fund_unit, optional: true
  belongs_to :document, optional: true

  validates :kind, inclusion: { in: DealingOrder::KINDS }
  validates :dealing_order_id, uniqueness: { scope: :dealing_date_id }
  validates :nav_per_unit_cents, presence: true

  def subscription?
    kind == "subscription"
  end

  def redemption?
    kind == "redemption"
  end

  def units_moved?
    fund_unit_id.present?
  end

  def net_payment_cents
    amount_cents.to_d - early_fee_cents.to_d
  end
end
