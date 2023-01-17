module HoldingScopes
  extend ActiveSupport::Concern

  included do
    scope :equity, -> { where(investment_instrument: "Equity") }
    scope :preferred, -> { where(investment_instrument: "Preferred") }
    scope :options, -> { where(investment_instrument: "Options") }
    scope :not_phantom_options, -> { where("investment_instrument= 'Options' and option_type <> 'Phantom'") }
    # scope :investor, -> { where(holding_type: "Investor") }
    # scope :employee, -> { where(holding_type: "Employee") }
    # scope :founder, -> { where(holding_type: "Founder") }

    scope :investors, -> { where(holding_type: "Investor") }
    scope :not_investors, -> { where("holding_type  <> 'Investor'") }
    scope :employees, -> { where(holding_type: "Employee") }
    scope :founders, -> { where(holding_type: "Founder") }
    scope :lapsed, -> { where(lapsed: true) }
    scope :not_lapsed, -> { where.not(lapsed: true) }

    scope :approved, -> { where(approved: true) }
    scope :not_approved, -> { where(approved: false) }

    scope :cancelled, -> { where(cancelled: true) }
    scope :not_cancelled, -> { where(cancelled: false) }
    scope :manual_vesting, -> { where(manual_vesting: true) }
    scope :not_manual_vesting, -> { where(manual_vesting: false) }
    scope :eq_and_pref, -> { where(investment_instrument: %w[Equity Preferred]) }
  end
end
