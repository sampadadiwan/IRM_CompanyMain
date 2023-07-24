class Reminder < ApplicationRecord
  belongs_to :entity
  belongs_to :owner, polymorphic: true
  has_many :notifications, as: :recipient, dependent: :destroy

  NESTED_ATTRIBUTES = %i[id note due_date email _destroy].freeze

  validates :note,  presence: true
  validates_presence_of :due_date, if: ->(o) { o.email.present? }

  scope :unsent, -> { where(sent: false) }
  scope :due_today, -> { where("due_date <= ?", Time.zone.today) }

  def send_reminder
    email.split(",").each do |user_email|
      user = User.find_by(email: user_email.strip)
      ReminderNotification.with(entity_id:, reminder_id: id).deliver_later(user) if user
    end
  end
end
