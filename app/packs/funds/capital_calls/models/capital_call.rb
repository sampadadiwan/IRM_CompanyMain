class CapitalCall < ApplicationRecord
  include Workflowable

  # Auto-assignment rules may also test "Imported" — the seeded Light journey rule routes on it.
  # The amounts are rolled up from remittances after commit, so they are always 0 when the call is
  # created — the only time a rule is checked — and are left out
  workflow_rule_fields extra: %w[manual_generation],
                       except: %w[call_amount collected_amount capital_fee other_fee]
  include WithCustomField
  include WithFolder
  include WithNextSteps
  include Trackable.new

  include RansackerAmounts.new(fields: %w[call_amount collected_amount capital_fee other_fee])
  include WithCustomNotifications

  include ForInvestor
  include BlocksDestroyWithFundUnits

  # Evergreen settlement records (created by a dealing date) get no journey of their own — the dealing
  # date's journey replaces it. The flag covers the create callback, before the dealing date links it.
  # Backward compatibility B4 — openspec/changes/open-ended-funds/design.md#backward-compatibility
  attr_accessor :evergreen_settlement_flag

  def skip_journey?
    evergreen_settlement_flag || (persisted? && DealingDate.exists?(subscription_call_id: id))
  end

  FEE_TYPES = ["Fees Part Of Capital", "Other Fees", "Investment Amount"].freeze
  CALL_BASIS = ["Percentage of Commitment", "Upload", "Investable Capital Percentage"].freeze

  STANDARD_COLUMNS = { "Name; text-col" => "name; text-col",
                       "Due Date; date-col" => "due_date; date-col",
                       "Call Amount; num-col" => "call_amount; num-col",
                       "Collected Amount; num-col" => "collected_amount; num-col",
                       "Due Amount; num-col" => "due_amount; num-col",
                       "Approved; text-col" => "approved; text-col" }.freeze
  belongs_to :entity
  belongs_to :fund, touch: true

  belongs_to :approved_by_user, class_name: "User", optional: true
  # Stores the prices for unit types for this call
  serialize :unit_prices, type: Hash
  # close_percentages is a native `json` column (see migration
  # AddClosePercentagesToCapitalCalls) — Rails' json type already casts it to/from a
  # Hash automatically. Layering `serialize type: Hash` on top double-decodes it: the
  # json type deserializes the column into a Hash first, then the YAML coder tries to
  # YAML-parse that Hash and blows up with "no implicit conversion of Hash into String".
  serialize :fund_closes, type: Array

  has_many :capital_remittances, dependent: :destroy
  has_many :capital_commitments, through: :capital_remittances
  has_many :committed_investors, through: :capital_commitments, source: :investor
  has_many :remittance_documents, through: :capital_remittances, source: :documents, class_name: "Document"

  # This is the list of call_fees to be pulled out of account entries for the folio
  has_many :call_fees, dependent: :destroy
  accepts_nested_attributes_for :call_fees, allow_destroy: true
  # This stores any formulas selected by the user, to be used for call_fee computation for the folio
  serialize :fee_formula_ids, type: Array

  validates_uniqueness_of :name, scope: :fund_id
  normalizes :name, with: ->(name) { name.strip.squeeze(" ") }
  validates :name, :due_date, :call_date, :percentage_called, presence: true
  validates :fund_closes, presence: true, unless: -> { call_basis == 'Upload' }
  # validates percentage_called is less than or equal to 100
  validates :percentage_called, numericality: { less_than_or_equal_to: 100 }
  validates :name, :fund_closes, length: { maximum: 255 }

  monetize :call_amount_cents, :amount_to_be_called_cents, :capital_fee_cents, :other_fee_cents, :collected_amount_cents, with_currency: ->(i) { i.fund.currency }

  # This is a list of commitments for which this call is applicable
  def applicable_to
    commitments = fund.capital_commitments

    # The call is applicable only to those commitments which have a fund_close specified in the call
    if fund_closes.nil? || fund_closes.include?("All")
      commitments
    else
      commitments.where(fund_close: fund_closes)
    end
  end

  before_save :setup_defaults
  def setup_defaults
    case call_basis
    when "Percentage of Commitment"
      self.amount_to_be_called_cents = 0
    when "Upload"
      self.percentage_called = 0
      self.amount_to_be_called_cents = 0
    else
      self.percentage_called = 0
    end

    self.generate_remittances = true if call_basis != "Upload"
  end

  def generate_capital_remittances(later: true)
    if call_basis != "Upload" && generate_remittances &&
       (saved_change_to_percentage_called? || saved_change_to_amount_to_be_called_cents? || saved_change_to_fund_closes?)
      if later
        CapitalCallJob.perform_later(id, "Generate")
      else
        CapitalCallJob.perform_now(id, "Generate")
      end
    end
  end

  # triggered_by_user_id is carried through only so a blocked send can be reported back to the
  # person who pressed the button — an in-app alert where they are already looking, not just an
  # email minutes later. Optional: nothing else depends on it, and a job enqueued by an older
  # deploy arrives with two arguments.
  def send_notification(triggered_by_user_id = nil)
    return unless approved? && send_call_notice_flag && !manual_generation

    CapitalCallJob.perform_later(id, "Notify", triggered_by_user_id)
  end

  # True once any investor has actually been emailed the call notice
  # (CapitalRemittance#notification_sent — a one-way flag, never reset). Used to warn
  # before Unapprove: reverting approval won't un-notify. Deliberately does not consider
  # CapitalRemittancePayment#payment_notification_sent — that's a separate notification
  # (payment received) triggered independently of call approval, unrelated to this warning.
  def any_remittance_notified?
    capital_remittances.exists?(notification_sent: true)
  end

  def folder_path
    "#{fund.folder_path}/Capital Calls/#{name.delete('/')}"
  end

  # Falls back to the fund's default CapitalCall notification (for_type: "CapitalCall") when this
  # specific call has no override of its own for the given email_method.
  def custom_notification(email_method, for_type: nil, custom_notification_id: nil)
    super || fund.custom_notification(email_method, for_type: "CapitalCall", custom_notification_id:)
  end

  delegate :to_s, to: :name

  def due_amount
    call_amount + other_fee - collected_amount
  end

  def percentage_raised
    call_amount_cents.positive? ? (collected_amount_cents * 100.0 / call_amount_cents).round(6) : 0
  end

  # Call-level "Capital Call Reminder" button (remittances tab). Sends the reminder template to
  # every Pending/Overdue remittance. Deliberately does NOT check send_call_notice_flag,
  # notification_sent or notice approval, and does not set notification_sent — see
  # docs/user_guides/capital_call_actions_and_notifications_matrix.md.
  # Returns the NotificationAttachmentPreflight::BlockedSend when the run was stopped, nil when
  # it went ahead. This one runs INSIDE the request (the remittances-tab Reminder button), so
  # the caller can turn a block into a flash immediately rather than reporting success and
  # leaving the operator to find out by email.
  def reminder_capital_call(triggered_by_user_id = nil)
    return unless approved?

    pending = capital_remittances.where(status: %w[Pending Overdue])

    # Same size preflight as the initial call notice (CapitalCallJob#notify): stop the whole
    # reminder run rather than letting an oversized attachment bounce recipient by recipient.
    blocked = NotificationAttachmentPreflight.batch_error_message(
      pending, custom_notification(:reminder_capital_remittance),
      context: "Cannot send call reminders for #{name}",
      # Matches the skip in the loop below, so a commitment this run would never email cannot
      # block the reminder for everyone else.
      skip_if: ->(cr) { cr.capital_commitment.skip_doc_gen? }
    ) { |cr| NotificationAttachmentPreflight.auto_attached_documents(cr) }
    if blocked.present?
      NotificationAttachmentPreflight.report_blocked_send(blocked, entity_id:, user_id: triggered_by_user_id,
                                                                   subject: "Capital call reminders not sent")
      return blocked
    end

    pending.find_each do |cr|
      next if cr.capital_commitment.skip_doc_gen?

      cr.investor.notification_users(fund, with_tag: 'CapitalCall').each do |user|
        CapitalRemittanceNotifier.with(record: cr, entity_id:, email_method: :reminder_capital_remittance, msg: "Capital Call Reminder: #{fund.name}").deliver_later(user)
      end
    end
  end

  def fund_units
    FundUnit.where(fund_id:, owner_type: "CapitalRemittance", owner_id: capital_remittance_ids)
  end

  def fee_account_entry_names
    fund.account_entries.where("name like '%Fee%' or name like '%Expense%'").pluck(:name).uniq << "Other"
  end

  def call_basis_list
    if entity.entity_setting.call_basis.present?
      CALL_BASIS + entity.entity_setting.call_basis.split(",")
    else
      CALL_BASIS
    end
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name due_date approved call_date call_amount collected_amount capital_fee other_fee percentage_called fund_id].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    ["fund"]
  end

  def fee_formulas
    fee_formula_ids.present? ? CallFee.where(id: fee_formula_ids) : CallFee.none
  end

  def all_call_fees
    call_fees + fee_formulas
  end

  # Workflowable interface uses all defaults from the concern:
  #   workflow_display_name → to_s
  #   workflow_url          → capital_call_path(self)
  #   workflow_attachable_files → []

  # The journey panel on the call page: real-time refresh, creator as default owner and
  # journey_progress_for all come from Workflowable. The panel is the only journey state on the page —
  # the Approve / Send confirmations deliberately don't repeat it — so its frame is all that can go stale.
  # Worked examples J2.2 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  has_journey

  # ── Live refresh of the call page's remittances list and stats cards ──────────────────────────
  # Remittances are created by CapitalCallJob in the background, and the stats cards read counter
  # caches that only CapitalRemittancesCountersJob fixes afterwards — so without these broadcasts the
  # page shows an empty list / old totals until the user reloads it. Both go out on one stream,
  # [call, :remittances], which show.html.erb subscribes to.
  #
  # Like DocChecks::Broadcast, they send a reload_frame action (app/javascript/custom/turbo_stream_actions.js)
  # rather than rendered HTML: each browser re-fetches the frame as its own user, so Pundit scoping and
  # the viewer's buttons stay right. Never raises — a cable/Redis hiccup must not fail the job.

  # The lazy remittances frame on the Remittances tab (capital_calls/_details)
  REMITTANCES_FRAME_ID = "capital_remittances_frame".freeze

  # The frame wrapping the stats cards at the top of the page (capital_calls/_stats_frame)
  def stats_frame_id
    "capital_call_#{id}_stats"
  end

  # Remittances were created or changed. No src: the browser reloads whatever the frame currently
  # shows, so a status/verified filter the user picked (remittances_controller.js) is kept.
  def broadcast_remittances_change
    broadcast_reload_frame(REMITTANCES_FRAME_ID)
  end

  # The call's rolled-up amounts changed (counters fixed). The stats frame renders without a src on
  # first load, so the src here is what makes the browser fetch GET /capital_calls/:id/stats.
  def broadcast_stats_change
    broadcast_reload_frame(stats_frame_id, src: Rails.application.routes.url_helpers.stats_capital_call_path(self))
  end

  # ── "Generating remittances… 1,240 of 5,000" while CapitalCallJob runs ──────────────────────
  # The text is the same for every viewer and has no buttons, so it is broadcast as rendered HTML
  # (unlike the frames above). It is also kept in the cache so a page opened mid-run shows it
  # straight away; the expiry clears a line the job never got to clear (a killed worker).

  def remittance_progress_target_id
    "capital_call_#{id}_remittance_progress"
  end

  def remittance_progress_cache_key
    "capital_call:#{id}:remittance_progress"
  end

  # { done:, total: } while a generation run is going, else nil
  def remittance_progress
    Rails.cache.read(remittance_progress_cache_key)
  end

  def broadcast_remittance_progress(done:, total:)
    Rails.cache.write(remittance_progress_cache_key, { done:, total: }, expires_in: 1.hour)
    Turbo::StreamsChannel.broadcast_update_to(self, :remittances, target: remittance_progress_target_id,
                                                                  partial: "capital_calls/remittance_progress", locals: { done:, total: })
  rescue StandardError => e
    Rails.logger.error("CapitalCall##{id} progress broadcast failed: #{e.class} #{e.message}")
  end

  # The run ended: forget the progress and empty the line on open pages
  def clear_remittance_progress
    Rails.cache.delete(remittance_progress_cache_key)
    Turbo::StreamsChannel.broadcast_update_to(self, :remittances, target: remittance_progress_target_id, html: "")
  rescue StandardError => e
    Rails.logger.error("CapitalCall##{id} progress clear failed: #{e.class} #{e.message}")
  end

  # Units that must be deleted before this record can be (see BlocksDestroyWithFundUnits)
  def allocated_fund_units
    FundUnit.where(owner_type: "CapitalRemittance", owner_id: capital_remittances.select(:id))
  end

  private

  # Sends the reload_frame stream action to every page showing this call. src is optional:
  # without one the browser reloads the frame from its current src.
  def broadcast_reload_frame(target, src: nil)
    attributes = src ? { src: } : {}
    Turbo::StreamsChannel.broadcast_action_to(self, :remittances, action: :reload_frame, target:, attributes:)
  rescue StandardError => e
    Rails.logger.error("CapitalCall##{id} broadcast to #{target} failed: #{e.class} #{e.message}")
  end
end
