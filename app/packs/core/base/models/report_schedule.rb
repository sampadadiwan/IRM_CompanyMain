class ReportSchedule < ApplicationRecord
  include Schedulable

  belongs_to :report

  # ReportSchedule's UI only exposes a frequency picker (no day-of-week/month picker
  # like AgentSchedule's), so weekly/monthly schedules always anchor to day 1
  # (Monday / the 1st), matching the hardcoded slot the old cron_expression implied.
  attribute :run_on_day, :integer, default: 1

  validates :frequency, inclusion: { in: %w[daily weekly monthly] }
  validates :recipients, presence: true

  serialize :recipients, type: Array, coder: JSON
end
