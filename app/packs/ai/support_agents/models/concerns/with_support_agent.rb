module WithSupportAgent
  extend ActiveSupport::Concern

  # The model implementing this, should have one support_agent_report
  included do
    has_one :support_agent_report, as: :owner, dependent: :destroy

    scope :with_completed_report, -> { joins(:support_agent_report).where(support_agent_reports: { status: "Completed" }) }
    scope :with_not_completed_report, -> { joins(:support_agent_report).where.not(support_agent_reports: { status: "Completed" }) }
    scope :with_failed_report, -> { joins(:support_agent_report).where(support_agent_reports: { status: "Failed" }) }

    attr_accessor :row_template
  end

  def broadcast_row(row_template: nil)
    row_template ||= get_row_template
    # Debug: log what will be broadcast so we can correlate server-side
    # broadcasts with client-side Turbo stream messages.
    target = "#{self.class.name.underscore}_#{id}"

    broadcast_replace_to self,
                         target: target,
                         partial: row_template,
                         locals: { self.class.name.underscore => self }
  end
end
