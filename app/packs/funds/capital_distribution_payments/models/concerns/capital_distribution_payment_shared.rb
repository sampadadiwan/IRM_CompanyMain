module CapitalDistributionPaymentShared
  extend ActiveSupport::Concern

  included do
    scope :completed, -> { where(completed: true) }
    scope :pending, -> { where(completed: false) }
  end
end
