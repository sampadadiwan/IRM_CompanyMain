module WithSupportAgent
  extend ActiveSupport::Concern

  # The model implementing this, should have one support_agent_report
  included do
    has_one :support_agent_report, as: :owner, dependent: :destroy

    scope :with_completed_report, -> { joins(:support_agent_report).where(support_agent_reports: { status: "Completed" }) }
    scope :with_not_completed_report, -> { joins(:support_agent_report).where.not(support_agent_reports: { status: "Completed" }) }
    scope :with_failed_report, -> { joins(:support_agent_report).where(support_agent_reports: { status: "Failed" }) }
  end
end
