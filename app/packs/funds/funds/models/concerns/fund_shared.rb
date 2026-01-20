module FundShared
  extend ActiveSupport::Concern

  included do
    # No common scopes identified in production that are needed here,
    # but we can add placeholders if necessary.

    scope :feeder_funds, -> { where.not(master_fund_id: nil) }
    scope :master_funds, -> { where(master_fund_id: nil) }
  end

  def to_s
    name
  end
end
