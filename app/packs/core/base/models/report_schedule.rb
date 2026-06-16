class ReportSchedule < ApplicationRecord
  belongs_to :report

  validates :frequency, presence: true, inclusion: { in: %w[daily weekly monthly] }
  validates :recipients, presence: true
  validates :cron_expression, presence: true

  serialize :recipients, type: Array, coder: JSON

  before_validation :set_cron_expression

  scope :active, -> { where(active: true) }

  def set_cron_expression
    return if cron_expression.present?

    self.cron_expression = { 'daily' => "0 9 * * *", 'weekly' => "0 9 * * 1", 'monthly' => "0 9 1 * *" }[frequency]
  end
end
