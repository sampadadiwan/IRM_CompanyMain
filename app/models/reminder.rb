class Reminder < ApplicationRecord
  belongs_to :entity
  belongs_to :owner, polymorphic: true
  NESTED_ATTRIBUTES = %i[id note due_date email _destroy].freeze

  scope :unsent, -> { where(sent: false) }
  scope :due_today, -> { where("due_date <= ?", Time.zone.today) }

  def send_reminder
    ReminderMailer.with(id:).send_reminder.deliver_later
  end
end
