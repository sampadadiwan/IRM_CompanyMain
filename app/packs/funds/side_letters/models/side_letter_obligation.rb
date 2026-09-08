# One obligation ("covenant") arising from a side letter — the source of truth
# from which tasks are only projections. Lifecycle:
#
#   pending_review --approve--> approved (status: active) --project--> tasks
#         \--reject--> rejected (never projects anything)
#
# Dated shapes (calendar_event with an RRULE, or one_time) project into the
# existing Task / TaskRecurrenceRule machinery on approval. Event-triggered and
# ongoing shapes stay "armed" — visible in the matrix with no task until a user
# fires them (ObligationFire).
class SideLetterObligation < ApplicationRecord
  OWNER_TEAMS = %w[ir finance legal deal_team operations].freeze

  belongs_to :entity
  # @return [SideLetter, nil] anchor for commitment-sourced obligations; nil for
  #   portfolio investment obligations which use sourceable instead
  belongs_to :side_letter, optional: true
  belongs_to :owner_user, class_name: "User", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true
  belongs_to :task_recurrence_rule, optional: true
  # @return [SideLetter, PortfolioInvestment, nil] Polymorphic source record.
  #   Existing side letter obligations use side_letter_id; portfolio investment
  #   obligations use this polymorphic link instead.
  belongs_to :sourceable, polymorphic: true, optional: true

  has_many :tasks, as: :owner, dependent: :destroy
  has_many :obligation_fulfillments, dependent: :destroy
  has_many :obligation_reminders, dependent: :destroy

  delegate :capital_commitment, :fund, :investor, to: :side_letter, allow_nil: true

  # @return [Investor, nil] The investor/portfolio company linked to this obligation,
  #   regardless of source. Commitment path: side_letter -> capital_commitment -> investor.
  #   Portfolio path: sourceable -> portfolio_company.
  def source_investor
    if sourceable_type == "PortfolioInvestment"
      sourceable&.portfolio_company
    else
      investor
    end
  end

  # @return [Fund, nil] The fund this obligation belongs to, regardless of source.
  #   Commitment path: side_letter -> fund. Portfolio path: sourceable -> fund.
  def source_fund
    if sourceable_type == "PortfolioInvestment"
      sourceable&.fund
    else
      fund
    end
  end

  enum :obligation_type, {
    reporting: "reporting", fees: "fees", co_investment: "co_investment",
    notice: "notice", transfer: "transfer", excuse: "excuse",
    confidentiality: "confidentiality", key_person: "key_person",
    mfn: "mfn", other: "other"
  }, prefix: :obl

  enum :trigger_type, {
    calendar_event: "calendar_event", fund_event: "fund_event",
    deal_event: "deal_event", status_change: "status_change",
    one_time: "one_time", ongoing: "ongoing"
  }, prefix: :trigger

  enum :review_status, {
    pending_review: "pending_review", approved: "approved", rejected: "rejected"
  }

  # nil until approved — an unreviewed obligation has no lifecycle status yet
  enum :status, {
    active: "active", fulfilled: "fulfilled", waived: "waived",
    expired: "expired", disputed: "disputed"
  }, prefix: :obligation

  enum :mfn_review_status, {
    not_reviewed: "not_reviewed", no_trigger: "no_trigger",
    triggered_matched: "triggered_matched", triggered_exception: "triggered_exception"
  }, prefix: :mfn

  enum :extracted_by, { manual: "manual", ai: "ai" }, prefix: :extracted_by

  # @return [String] Legal classification assigned by the LLM during extraction.
  #   CP = must be satisfied before an event; CS = ongoing with breach consequences;
  #   SLO = standard promise/covenant. Counsel can correct before approval.
  enum :legal_category, {
    condition_precedent: 0, condition_subsequent: 1, side_letter_obligation: 2
  }, prefix: :legal

  validates :title, presence: true
  validates :owner_team, inclusion: { in: OWNER_TEAMS }, allow_blank: true
  # The review gate discards citation-less AI output before persisting; this
  # backstops it at the model so a hallucinated row can never slip in silently.
  validates :source_clause, presence: true, if: :extracted_by_ai?

  scope :pending_review, -> { where(review_status: "pending_review") }
  scope :approved, -> { where(review_status: "approved") }
  scope :active, -> { where(status: "active") }
  # Armed = approved but not date-driven: surfaced in the matrix, no task yet
  scope :armed, -> { approved.where(trigger_type: %w[fund_event deal_event status_change ongoing]) }

  # An owner is mandatory before approval — someone must be on the hook.
  def owner_present?
    owner_user_id.present? || owner_team.present?
  end

  # Date-driven shapes that project tasks on approval
  def recurring?
    trigger_calendar_event? && frequency_rrule.present?
  end

  def dated?
    recurring? || trigger_one_time?
  end

  def armed?
    approved? && !dated?
  end

  # Human label for the matrix "Owner" column: user takes precedence over team
  def owner_label
    owner_user&.first_name.presence || owner_team&.humanize
  end

  # Shown wherever a task's owner is rendered (tasks grid "For" column etc.)
  def to_s
    title
  end

  # Called by Task#register_owner_interaction (duck-typed hook) whenever a task
  # owned by this obligation is completed — records the fulfillment audit row
  # and closes out one-time obligations.
  def register_task_completion(task)
    obligation_fulfillments.find_or_create_by!(task: task) do |fulfillment|
      fulfillment.entity_id = entity_id
      fulfillment.fulfilled_at = task.completed_on || Time.zone.today
      fulfillment.fulfilled_by_id = task.assigned_to_id || task.user_id
      fulfillment.fulfillment_method = "Completed task: #{task.display_details.truncate(120)}"
    end
    update!(status: "fulfilled") if trigger_one_time? && approved?
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[obligation_type title owner_team trigger_type review_status status
       next_due_date mfn_relevant source_clause legal_category]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[side_letter owner_user]
  end
end
