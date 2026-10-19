# A background operation support runs on a fund's formulas from the fund formulas page, previewed
# first and (except for suggestions) applied afterwards. One row per request, kept whatever the
# outcome, so the table is also the history of who changed which fund.
#
#   enable_incremental / disable_incremental  AccountEntryAllocation::IncrementalMigration
#   reseed_carry_forward                      recompute tracking formulas' stored starting values
#   suggest_checks                            RunCheckSuggestions: pre/post-run check formulas
#
# Status flow:
#   previewing -> previewed | blocked | failed
#   previewed  -> applying  -> applied | refused | failed
# A suggestion set stays "previewed"; each "Add selected" is appended to result["added"].
#
# See openspec/changes/incremental-allocation-ui/design.md.
class FundFormulaOperation < ApplicationRecord
  OPERATIONS = %w[enable_incremental disable_incremental reseed_carry_forward suggest_checks].freeze
  # Operations that have an apply step
  APPLICABLE = %w[enable_incremental disable_incremental reseed_carry_forward].freeze

  # Not an ActiveRecord enum: "failed"/"applied" scopes would be fine, but plain predicates match
  # AllocationRunReport and keep the string values visible in queries.
  STATUSES = %w[previewing previewed blocked applying applied refused failed].freeze
  ACTIVE_STATUSES = %w[previewing applying].freeze

  # An allocation run or operation still "in progress" after this long is taken to have crashed:
  # runs take minutes, and a crashed job would otherwise block the fund for ever.
  STALE_AFTER = 12.hours

  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :requested_by, class_name: "User"
  belongs_to :applied_by, class_name: "User", optional: true

  validates :operation, inclusion: { in: OPERATIONS }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :active, -> { where(status: ACTIVE_STATUSES) }
  # Active and recent enough to still be running
  scope :live, -> { active.where(updated_at: STALE_AFTER.ago..) }
  scope :stale, -> { active.where(updated_at: ...STALE_AFTER.ago) }
  scope :incremental, -> { where(operation: %w[enable_incremental disable_incremental]) }

  STATUSES.each { |s| define_method(:"#{s}?") { status == s } }

  def active? = ACTIVE_STATUSES.include?(status)
  def applicable? = APPLICABLE.include?(operation)
  def suggestions? = operation == "suggest_checks"

  # Apply is offered only on a finished, unblocked preview of an operation that has an apply step
  def can_apply? = applicable? && previewed?

  # Marks operations whose job never finished as failed, so they stop blocking the fund.
  def self.fail_stale!(fund_id)
    stale.where(fund_id:).find_each do |operation|
      operation.update!(status: "failed", error: "Did not finish within #{STALE_AFTER.inspect}; treated as failed")
    end
  end

  # Starts a preview in the background, unless another operation on the fund is still in progress.
  # @return [FundFormulaOperation] the new operation, or the one already in progress (then not new_preview?)
  def self.start!(fund:, operation:, user:, params: {})
    started = new(entity_id: fund.entity_id, fund:, operation:, requested_by: user, status: "previewing", params:)
    started.validate!
    in_progress = nil
    fund.with_lock do
      fail_stale!(fund.id)
      in_progress = live.find_by(fund_id: fund.id)
      started.save! unless in_progress
    end
    return in_progress if in_progress

    FundFormulaOperationJob.perform_later(started.id, "preview")
    started.tap { |o| o.new_preview = true }
  end

  attr_accessor :new_preview

  def new_preview? = new_preview == true

  # Queues the apply step, unless the preview cannot be applied or the fund is busy.
  # @return [String, nil] why it was not queued
  def start_apply!(user)
    return "This preview cannot be applied." unless can_apply?

    refusal = nil
    fund.with_lock do
      self.class.fail_stale!(fund_id)
      # Checked again under the lock: a second Apply (a double click, two tabs) queues here until the
      # first one has set "applying", and must not queue a second apply job
      reload
      refusal = if applying? then "This preview is already being applied."
                elsif !can_apply? then "This preview cannot be applied."
                else FundAllocationActivity.new(fund).reason(except: self)
                end
      update!(status: "applying", applied_by: user) unless refusal
    end
    return refusal if refusal

    FundFormulaOperationJob.perform_later(id, "apply")
    nil
  end

  # --- Suggestion sets ---------------------------------------------------------------------------------

  SEVERITIES = %w[fail warning].freeze

  def suggestion_list
    @suggestion_list ||= Array(plan.to_h["suggestions"]).map { |h| AccountEntryAllocation::RunCheckSuggestions::Suggestion.new(h) }
  end

  # The chosen suggestions, at the chosen severities ({key => "fail" | "warning"})
  def selected_suggestions(keys, severities = {})
    keys = Array(keys).to_set(&:to_s)
    severities = severities.to_h.stringify_keys
    suggestion_list.select { |s| keys.include?(s.key) }.map do |s|
      copy = AccountEntryAllocation::RunCheckSuggestions::Suggestion.new(s.to_h.deep_dup)
      copy["severity"] = severities[s.key] if s.supports_severity? && SEVERITIES.include?(severities[s.key])
      copy
    end
  end

  # Addable now: valid, and no check making the same call exists on the fund today (it may have been
  # added since the set was generated)
  def addable?(suggestion)
    return false if suggestion.errors.present?

    @existing_checks ||= fund.fund_formulas.run_checks.pluck(:formula).map { |f| AccountEntryAllocation::RunCheckSuggestions::Builder.comparable(f) }
    SEVERITIES.none? { |sev| @existing_checks.include?(AccountEntryAllocation::RunCheckSuggestions::Builder.comparable(suggestion.formula(severity: sev))) }
  end

  # Adds the chosen suggestions as enabled check formulas, recording what was added in result["added"].
  # @return [Hash] { added: [[key, formula_id]], failed: [[name, reason]] }
  def add_suggestions!(keys:, user:, severities: {})
    added = []
    failed = []
    selected_suggestions(keys, severities).each do |suggestion|
      next failed << [suggestion.name, "already present or not valid"] unless addable?(suggestion)

      formula = fund.fund_formulas.create(**suggestion.formula_attributes, entity_id:)
      if formula.persisted?
        added << [suggestion.key, formula.id]
        @existing_checks << AccountEntryAllocation::RunCheckSuggestions::Builder.comparable(formula.formula) # addable? loaded it
      else
        failed << [suggestion.name, formula.errors.full_messages.to_sentence]
      end
    end
    if added.any?
      entry = { "by" => user.id, "at" => Time.current.iso8601, "keys" => added.map(&:first), "formula_ids" => added.map(&:last) }
      update!(result: result.to_h.merge("added" => Array(result.to_h["added"]) + [entry]))
    end
    { added:, failed: }
  end

  # The chosen suggestions as an xlsx in the fund formula import format
  def suggestions_xlsx(keys:, severities: {})
    FundFormulaAttributes.to_xlsx(selected_suggestions(keys, severities).map(&:formula_attributes))
  end

  def to_s
    "#{operation.humanize} ##{id}"
  end
end
