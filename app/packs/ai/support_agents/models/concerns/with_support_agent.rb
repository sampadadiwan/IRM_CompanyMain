module WithSupportAgent
  extend ActiveSupport::Concern

  # The model implementing this, should have one support_agent_report
  included do
    has_one :support_agent_report, as: :owner, dependent: :destroy
  end
end
