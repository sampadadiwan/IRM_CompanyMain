# Log of every obligation alert actually sent by the enforcement run. Doubles
# as the idempotency guard: at most one upcoming and one due alert per
# obligation per due date, and overdue re-alerts only after the escalation
# interval (see SideLetterObligationAgent#enforce).
class ObligationReminder < ApplicationRecord
  KINDS = %w[upcoming due overdue].freeze

  belongs_to :entity
  belongs_to :side_letter_obligation
  belongs_to :task, optional: true
  belongs_to :recipient_user, class_name: "User", optional: true

  enum :kind, { upcoming: "upcoming", due: "due", overdue: "overdue" }

  validates :kind, presence: true
  # One-shot kinds are unique per due date; overdue repeats on the escalation
  # cadence so it is deliberately excluded from this uniqueness rule.
  validates :kind, uniqueness: { scope: %i[side_letter_obligation_id due_date] },
                   unless: :overdue?

  # Has an overdue alert gone out within the escalation window? Used to decide
  # whether it is time to re-alert.
  def self.overdue_sent_within?(obligation, task, days)
    overdue.where(side_letter_obligation: obligation, task: task)
           .where(sent_at: days.days.ago..)
           .exists?
  end
end
