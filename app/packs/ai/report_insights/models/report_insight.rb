class ReportInsight < ApplicationRecord
  belongs_to :entity
  belongs_to :report

  belongs_to :triggered_by_user, class_name: "User", foreign_key: "triggered_by_id", optional: true

  STATUSES = %w[success failed running pending].freeze

  validates :status, inclusion: { in: STATUSES }, allow_nil: true
  validates :trigger_type, inclusion: { in: %w[manual system] }, allow_nil: true

  # status can be ["success", "failed", "running", "pending"]
  def status_badge
    case status&.downcase
    when "success"
      "success"
    when "failed"
      "danger"
    when "running"
      "info"
    else
      "secondary"
    end
  end
end
