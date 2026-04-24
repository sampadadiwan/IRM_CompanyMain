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

    self.cron_expression = case frequency
                           when 'daily'   then "0 9 * * *"      # 9 AM daily
                           when 'weekly'  then "0 9 * * 1"      # 9 AM every Monday
                           when 'monthly' then "0 9 1 * *"      # 9 AM on the 1st of every month
                           end
  end
end
