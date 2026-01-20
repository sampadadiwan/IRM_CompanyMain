module CapitalRemittanceShared
  extend ActiveSupport::Concern

  included do
    scope :paid, -> { where(status: "Paid") }
    scope :unpaid, -> { where(status: "Pending") }
    scope :pending, -> { where(status: "Pending") }
    scope :verified, -> { where(verified: true) }
    scope :unverified, -> { where(verified: false) }
  end
end
