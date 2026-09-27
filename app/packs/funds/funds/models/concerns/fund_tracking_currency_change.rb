# State of a support-initiated change of a fund's tracking currency (ChangeTrackingCurrencyJob).
#
# Changing funds.tracking_currency is not a one-column edit: every stored tracking amount has to be
# rebuilt at historical rates, in a background job. Two columns record that a change is under way:
#
#   tracking_currency_change_state  nil (idle) | "in_progress" | "failed"
#   tracking_currency_changing_to   the target currency; nil with a state set means "remove it"
#   tracking_currency_change_started_at  when the change was claimed (or last retried)
#
# The state is also the lock. #claim_tracking_currency_change! sets it with a conditional UPDATE, so
# of two concurrent requests exactly one wins. While it is set:
#   - the nightly/entity-wide TrackingCurrencyJob skips the fund (Fund.without_tracking_currency_change),
#   - new allocation runs on the fund are refused (AllocationRun validation, FundsController#allocate),
#   - the fund page shows a banner, with a Retry button once the state is "failed".
#
#   fund.claim_tracking_currency_change!("EUR")   # => true, or false if a change is already pending
#   fund.release_tracking_currency_change!        # back to idle, after success or a validation abort
module FundTrackingCurrencyChange
  extend ActiveSupport::Concern

  CHANGE_IN_PROGRESS = "in_progress".freeze
  CHANGE_FAILED = "failed".freeze
  # The job runs with retry: 0 and releases its own claim, so a hard-killed worker (OOM, deploy
  # SIGKILL) or a failed enqueue leaves the fund in progress with nothing left to finish it. After
  # this long a change still in progress is treated as dead and can be retried, as a failed one can.
  # Same horizon as FundFormulaOperation::STALE_AFTER.
  STALE_AFTER = 12.hours

  included do
    scope :without_tracking_currency_change, -> { where(tracking_currency_change_state: nil) }
  end

  # true from the moment support submits a change until it completes, and while a failed change
  # awaits a retry - the tracking amounts cannot be trusted in either case.
  def tracking_currency_change_pending?
    tracking_currency_change_state.present?
  end

  def tracking_currency_change_failed?
    tracking_currency_change_state == CHANGE_FAILED
  end

  # In progress for longer than STALE_AFTER: the job that claimed it is taken to be dead. A claim
  # with no start time predates the column and is treated the same way.
  def tracking_currency_change_stale?
    tracking_currency_change_state == CHANGE_IN_PROGRESS &&
      (tracking_currency_change_started_at.nil? || tracking_currency_change_started_at < STALE_AFTER.ago)
  end

  # A failed change, or one whose job died, can be re-run (FundsController#retry_tracking_currency_change).
  def tracking_currency_change_retryable?
    tracking_currency_change_failed? || tracking_currency_change_stale?
  end

  # Currencies the fund can be tracked in: any currency the entity has exchange rates for, plus
  # its own. Offered by the fund form and the change form, and checked by the controller.
  def tracking_currency_options
    rates = entity.exchange_rates
    (rates.distinct.pluck(:from) + rates.distinct.pluck(:to) + [entity.currency]).compact_blank.uniq.sort
  end

  # Claims the fund for a change to new_currency (blank = remove the tracking currency).
  # @return [Boolean] false when another change is already in progress or awaiting a retry
  def claim_tracking_currency_change!(new_currency)
    claimed = Fund.where(id:, tracking_currency_change_state: nil)
                  .update_all(tracking_currency_change_state: CHANGE_IN_PROGRESS,
                              tracking_currency_changing_to: new_currency.presence,
                              tracking_currency_change_started_at: Time.current) == 1
    reload if claimed
    claimed
  end

  # Moves a failed or stale change back to in progress, keeping its target, for a retry. The same
  # conditional UPDATE as the claim, so two concurrent retries start one job, not two.
  # @return [Boolean] false unless the change is currently failed or stale
  def reclaim_failed_tracking_currency_change!
    retryable = Fund.where(tracking_currency_change_state: CHANGE_FAILED)
                    .or(Fund.where(tracking_currency_change_state: CHANGE_IN_PROGRESS,
                                   tracking_currency_change_started_at: [nil, ...STALE_AFTER.ago]))
    reclaimed = Fund.where(id:).merge(retryable)
                    .update_all(tracking_currency_change_state: CHANGE_IN_PROGRESS,
                                tracking_currency_change_started_at: Time.current) == 1
    reload if reclaimed
    reclaimed
  end

  # Identifies one claim (or retry) of the change. ChangeTrackingCurrencyJob is enqueued with it and
  # settles the claim only while it still matches: a stale-claim Retry starts a new job with a new
  # token, and the old job - which may only have been stuck in the queue, not dead - must then not
  # release or fail the change the new one is running (a failed state with its target already
  # cleared would make the next Retry remove the tracking currency).
  def tracking_currency_change_token
    tracking_currency_change_started_at&.utc&.iso8601(6)
  end

  # The marker columns are bookkeeping, not fund data: written without callbacks or an audit row.
  # (The currency itself is audited when ChangeTrackingCurrencyJob saves it.)
  #
  # claim: :any settles whatever change is pending (the controller, undoing its own claim); a token
  # (nil for a claim made before the start time was recorded) settles only that claim.
  # @return [Boolean] false when the claim was no longer the one given
  def mark_tracking_currency_change_failed!(claim: :any)
    settle_tracking_currency_change(claim, tracking_currency_change_state: CHANGE_FAILED)
  end

  def release_tracking_currency_change!(claim: :any)
    settle_tracking_currency_change(claim, tracking_currency_change_state: nil, tracking_currency_changing_to: nil,
                                           tracking_currency_change_started_at: nil)
  end

  private

  def settle_tracking_currency_change(claim, attributes)
    scope = Fund.where(id:)
    scope = scope.where(tracking_currency_change_started_at: claim && Time.iso8601(claim)) unless claim == :any
    settled = scope.update_all(attributes) == 1
    if settled
      assign_attributes(attributes)
      clear_attribute_changes(attributes.keys)
    end
    settled
  end
end
