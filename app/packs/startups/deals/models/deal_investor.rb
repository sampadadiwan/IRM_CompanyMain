class DealInvestor < ApplicationRecord
  include Trackable.new
  include WithFolder
  include ForInvestor
  include KanbanCardManager
  include WithCustomField
  include RansackerAmounts.new(fields: %w[total_amount primary_amount secondary_investment fee])
  include WithFriendlyId
  include WithIncomingEmail

  monetize  :fee_cents, :pre_money_valuation_cents, :secondary_investment_cents,
            :primary_amount_cents, :total_amount_cents, with_currency: ->(i) { i.deal.currency }
  # Make all models searchable
  update_index('deal_investor') { self if index_record? }

  has_rich_text :notes
  # touch deal runs after save when any of the following fields change: status, primary_amount_cents, secondary_investment_cents, fee_cents, pre_money_valuation_cents, deal_activity_id
  # we dont want to touch the deal on every save, as deal_investor gets updated a lot with callbacks from notes/tasks
  belongs_to :deal
  belongs_to :investor
  belongs_to :entity
  # This is the currently active activity for the investor
  belongs_to :deal_activity, optional: true
  counter_culture :entity

  has_many :deal_activities, -> { order(sequence: :asc) }, dependent: :destroy
  has_many :tasks, as: :owner, dependent: :destroy
  has_many :inv_notes, as: :owner, dependent: :destroy, class_name: "Note"

  # Non-persisted actor used to attribute initial step task generation.
  attr_accessor :created_by_user_id

  delegate :name, to: :entity, prefix: :entity
  delegate :name, to: :deal, prefix: :deal

  validates :status, :primary_amount_cents, :pre_money_valuation, presence: true
  validates :investor_id, uniqueness: { scope: :deal_id, message: "already added to this deal. Duplicate Investor." }
  validates :status, :tier, length: { maximum: 20 }
  validates :company_advisor, :investor_advisor, length: { maximum: 100 }
  validates :deal_lead, :source, :tags, length: { maximum: 255 }

  STATUS = %w[Active Pending Declined].freeze
  STANDARD_COLUMNS = {
    "Investor Name; text-col" => "investor_name; text-col",
    "Status; text-col" => "status; text-col",
    "Primary Amount; num-col" => "primary_amount; num-col",
    "Secondary Investment; num-col" => "secondary_investment; num-col",
    "Pre Money Valuation; num-col" => "pre_money_valuation; num-col",
    "Fee; num-col" => "fee; num-col",
    "Total Amount; num-col" => "total_amount; num-col",
    "Tier; text-col" => "tier; text-col",
    "Deal Lead; text-col" => "deal_lead; text-col",
    "Source; text-col" => "source; text-col",
    "Investor Advisor; text-col" => "investor_advisor; text-col",
    "Company Advisor; text-col" => "company_advisor; text-col",
    "Notes; text-col" => "notes; text-col",
    "Tags; text-col" => "tags; text-col",
    "Health Score; num-col" => "health_score; num-col",
    "Last Interaction; date-col" => "last_interaction_date; date-col"
  }.freeze

  CARD_VIEW_ATTRS = {
    "Pre Money Valuation" => "pre_money_valuation",
    "Primary Amount" => "primary_amount",
    "Secondary Investment" => "secondary_investment",
    "Fee" => "fee",
    "Total Amount" => "total_amount",
    "Tier" => "tier",
    "Status" => "status",
    "Deal Lead" => "deal_lead",
    "Source" => "source",
    "Notes" => "notes",
    "Tags" => "tags"
  }.freeze

  scope :for, ->(user) { where("investors.investor_entity_id=?", user.entity_id).joins(:investor) }
  scope :not_declined, -> { where("deal_investors.status<>?", "Declined").joins(:investor) }

  before_validation :calc_total_amount
  before_save :set_investor_entity_id
  before_save :track_status_change
  # Changes that mean someone actually worked this investor. deal_activity_id is
  # how a completed step shows up here: PerformActivityAction moves the investor
  # on to the next step and saves.
  #
  # Deliberately not "any save". WithFolder saves the record the first time its
  # document folder is needed — that is, on merely opening the sidepanel — and
  # messages_viewed writes read counters. Neither is an interaction, and both
  # would otherwise shuffle the grid just for looking at it.
  INTERACTION_ATTRIBUTES = %w[
    status primary_amount_cents secondary_investment_cents
    fee_cents pre_money_valuation_cents deal_activity_id
  ].freeze

  after_save :touch_deal, if: :interaction_change?
  after_save :register_own_interaction, if: :interaction_change?

  def interaction_change?
    saved_changes.keys.intersect?(INTERACTION_ATTRIBUTES)
  end

  def touch_deal
    deal&.touch
  end

  # ---------------------------------------------------------------------------
  # last_interaction_date — the deals grid's default sort key
  #
  # Three things count as an interaction:
  #   * a note's `on` date          (Note#update_investor)
  #   * a task's completed_on       (Task#register_owner_interaction)
  #   * a meaningful edit to the investor itself, including completing a step,
  #     which registers today (register_own_interaction above)
  #
  # The first two are dates the *user* asserts rather than timestamps we observe,
  # so a note typed today about a meeting in March must not move the investor.
  # All writers use update_column: a note/task save must not cascade back through
  # this model's callbacks (touch_deal, Chewy indexing, calc_total_amount), and
  # updated_at is the tiebreaker for rows that have no interaction date at all —
  # bumping it here would defeat that.
  # ---------------------------------------------------------------------------

  def register_own_interaction
    register_interaction(Time.zone.today)
  end

  # The incremental rule, used from the UI: only ever moves forward.
  def register_interaction(date)
    return if date.blank?

    date = date.to_date if date.respond_to?(:to_date)
    return if last_interaction_date.present? && last_interaction_date >= date

    update_column(:last_interaction_date, date)
  end

  # The full recompute, used after a bulk note upload. Imported notes arrive in any
  # order and may be backdated, so "only if larger" would settle on whichever row
  # happened to be processed last rather than the true maximum. Writes nil when
  # nothing carries a date.
  #
  # Notes and completed tasks only — this deliberately does not fold in the
  # today-stamp that register_own_interaction leaves. The same import writes the
  # investor rows (statuses, amounts) moments earlier, so including it would put
  # every imported investor on today's date and bury the historical "On" dates the
  # upload exists to carry.
  def recompute_last_interaction_date!
    latest = [inv_notes.maximum(:on), tasks.completed.maximum(:completed_on)].compact.max
    update_column(:last_interaction_date, latest)
  end

  def set_investor_entity_id
    self.investor_entity_id = investor.investor_entity_id
    self.investor_name = investor.investor_name
  end

  def track_status_change
    return unless self.class.column_names.include?('status_changed_at')

    self.status_changed_at = Time.current if status_changed?
  end

  def calc_total_amount
    self.total_amount_cents = primary_amount_cents + secondary_investment_cents + fee_cents
  end

  after_create_commit :create_activities_later

  def create_activities_later
    GenerateDealActivitiesJob.perform_later(id, "DealInvestor", created_by_user_id)
  end

  def name
    investor_name
  end

  def to_s
    investor_name
  end

  def main_folder_name
    investor_name
  end

  def parent_folder_name
    "Deals"
  end

  def short_name
    names = investor_name.to_s.split("-")
    second = names[1]&.strip
    %w[Employees Founders].include?(second) ? second : names[0]
  end

  def total
    primary_amount + secondary_investment + fee
  end

  def current_deal_activity_id
    return nil if deal_activity.blank?

    current_deal_activity = deal_activities.where.not(status: DealActivity.statuses["Template"]).find_by(title: deal_activity.title)
    current_deal_activity&.id
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[total_amount investor_name tier tags source deal_lead primary_amount secondary_investment fee last_interaction_date]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[deal deal_activity deal_activities]
  end

  def create_activities
    start_date = deal.start_date
    by_date = nil
    seq = 1
    days_to_completion = 0

    DealActivity.templates(deal).each do |template|
      if start_date
        days_to_completion += template.days
        by_date = start_date + days_to_completion.days
      end

      existing = DealActivity.where(deal_id:, deal_investor_id: id, entity_id:, template_id: template.id).first

      # When creating or updating the activity for an investor, we copy the tasks_csv and notification flags from the template.
      # This allows the automation to know which tasks belong to this investor's current step and when to notify.
      if existing
        existing.update(title: template.title, sequence: template.sequence, days: template.days, by_date:, template_id: template.id, docs_required_for_completion: entity.activity_docs_required_for_completion, details_required_for_na: entity.activity_details_required_for_na, tasks_csv: template.tasks_csv, notify_employees: template.notify_employees, notify_investor: template.notify_investor)
      else
        DealActivity.create(deal_id:, deal_investor_id: id, entity_id:, template_id: template.id, title: template.title, sequence: template.sequence, days: template.days, by_date:, docs_required_for_completion: entity.activity_docs_required_for_completion, details_required_for_na: entity.activity_details_required_for_na, tasks_csv: template.tasks_csv, notify_employees: template.notify_employees, notify_investor: template.notify_investor)
      end

      seq += 1
    end
  end

  def set_deal_investor_activity(user_id = nil)
    # After activities are created, set the deal_investor to the first incomplete activity (lowest sequence).
    # Only set it if not already pointing to a valid activity.
    return if deal_activity_id.present? && deal_activities.exists?(template_id: deal_activity_id)

    first_activity = deal_activities.where(status: "incomplete").order(:sequence).first
    return unless first_activity

    # deal_activity_id stores the template id, not the investor-specific instance id
    update_column(:deal_activity_id, first_activity.template_id)

    # Ensure tasks for the initial step are generated immediately after assigning current step.
    GenerateDealStepTasksJob.perform_later(id, user_id, first_activity.id)
  end

  def messages_viewed(current_user)
    if current_user.entity_id == investor_entity_id
      self.unread_messages_investor = 0
    else
      self.unread_messages_investee = 0
    end

    save
  end

  def folder_path
    "#{deal.folder_path}/Deal Investors/#{investor_name&.delete('/')}"
  end

  def folder_type
    :regular
  end

  def health_score
    return 0 if deal_activities.blank?

    total_count = deal_activities.size
    completed_count = deal_activities.count { |a| a.status == "Complete" }
    ((completed_count.to_f / total_count) * 100).round
  end

  def stagnant?
    return false if %w[Declined Complete].include?(status)

    updated_at < 7.days.ago
  end

  def stagnant_reason
    return nil unless stagnant?

    "No activity for more than 7 days"
  end

  def access_rights_changed(access_right)
    # Add the advisor name for easy access
    self.investor_advisor = Investor.owner_access_rights(self, "Advisor").pluck(:investor_name).join(",")
    save

    ar = AccessRight.where(id: access_right.id).first
    if ar
      # Ensure the advisor is also added to the deal
      deal_access_right = ar.dup
      deal_access_right.owner = deal
      deal_access_right.access_type = "Deal"
      deal_access_right.permissions = 0
      deal_access_right.permissions.set(:read)
      deal_access_right.save
    else
      deal.access_rights.where(access_to_investor_id: access_right.access_to_investor_id, access_to_category: access_right.access_to_category, user_id: access_right.user_id).find_each(&:destroy)
    end
  end
end
