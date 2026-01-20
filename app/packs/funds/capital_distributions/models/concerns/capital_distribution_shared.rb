module CapitalDistributionShared
  extend ActiveSupport::Concern

  included do
    enum :distribution_on, ["Commitment Percentage", "Investable Capital Percentage", "Upload"]
  end
end
