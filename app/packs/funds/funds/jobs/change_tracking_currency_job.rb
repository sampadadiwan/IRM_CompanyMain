# Changes a fund's tracking currency and rebuilds everything derived from it. Support-only; started
# from Fund > Actions > Change Tracking Currency (FundsController#change_tracking_currency).
#
# Why a job and not a form field: every tracking amount is stored in the tracking currency, while
# the currency *label* is read live from funds.tracking_currency by each model's monetize. Editing
# the column alone relabels old-currency numbers as the new currency, and the nightly
# TrackingCurrencyJob never repairs them (it only fills rows whose tracking amount is still 0).
#
# Same shape as ChangeFundCurrencyJob: validate everything, then write.
#   1. Check a fund.currency -> new currency rate exists for every date that will be converted
#      (TrackingRateValidator). If any is missing, stop with the fund untouched and say which.
#   2. Save the new tracking currency, audited as the support user who asked for it.
#   3. Rebuild every tracking amount at its own date's rate (TrackingCurrencyJob#rebuild_fund), or,
#      when the tracking currency is removed / set to the fund currency, zero them all.
#   4. Re-queue fund ratios for every end date that has them (FundRatioRecompute), which also
#      replaces ratios named after the old currency ("XIRR (EUR)").
#
# The controller claims the fund (Fund#claim_tracking_currency_change!) before enqueueing; this job
# reads the target from funds.tracking_currency_changing_to and releases the claim when done. If a
# step raises, the claim is left in the "failed" state rather than released: the tracking amounts
# are then half rebuilt, and the fund page says so and offers a Retry, which re-runs this job. That
# is safe because every step is idempotent - the save is skipped once the currency is already set,
# and the rebuild always recomputes from the fund-currency amounts (force).
class ChangeTrackingCurrencyJob < ApplicationJob
  queue_as :low
  # Retries are explicit (the Retry button), so a support user sees each attempt's outcome.
  sidekiq_options retry: 0

  # @param fund_id [Integer]
  # @param user_id [Integer] the support user who requested the change
  # @param claim [String, nil] Fund#tracking_currency_change_token of the claim this run was enqueued
  #   for; nil for a job enqueued before claims carried a start time
  def perform(fund_id, user_id, claim = nil)
    fund = Fund.find(fund_id)
    # Released, failed or re-claimed by a retry since the enqueue - nothing claimed for this run.
    return unless fund.tracking_currency_change_state == FundTrackingCurrencyChange::CHANGE_IN_PROGRESS &&
                  fund.tracking_currency_change_token == claim

    @claim = claim

    # Sent only once the claim is released (or left failed): a notification that raises must not
    # reach the rescue in #change_tracking_currency, which would mark a finished change "failed"
    # after the target column is cleared - and a Retry of that would wipe the tracking currency.
    message, level = change_tracking_currency(fund, user_id)
    send_notification(message, user_id, level)
  end

  private

  # Does the change while holding the claim, and releases it (or leaves it failed).
  # @return [Array(String, String)] the notification message and level for the outcome
  def change_tracking_currency(fund, user_id)
    new_currency = fund.tracking_currency_changing_to
    label = new_currency || "none"

    missing = TrackingRateValidator.call(fund, new_currency)
    return missing_rates_outcome(fund, new_currency, label, missing) if missing.any?

    save_tracking_currency(fund, new_currency, user_id)
    rebuild_tracking_amounts(fund, user_id)

    queued = FundRatioRecompute.call(fund, user_id)
    fund.release_tracking_currency_change!(claim: @claim)
    outcome = new_currency ? "Tracking amounts rebuilt" : "Tracking amounts cleared"
    ["#{fund.name}: tracking currency is now #{label}. #{outcome}; " \
     "fund ratios queued for #{queued} end date(s). Please refresh.", "success"]
  rescue StandardError => e
    fund.mark_tracking_currency_change_failed!(claim: @claim)
    send_notification("#{fund.name}: tracking currency change failed - #{e.message}. " \
                      "Tracking figures may be partly rebuilt; use Retry on the fund page.", user_id, "danger")
    raise
  end

  # The controller refuses a change to the currency already set, so the fund already holding the
  # target means an earlier attempt saved it and then failed mid-rebuild: the tracking amounts are
  # partly converted. Releasing then would hide that behind "nothing was changed" and drop the
  # Retry - leave the change failed instead, so it can be retried once the rates are added.
  def missing_rates_outcome(fund, new_currency, label, missing)
    rates = "Missing exchange rates - #{missing.join('; ')}"
    if fund.tracking_currency.presence == new_currency
      fund.mark_tracking_currency_change_failed!(claim: @claim)
      ["#{fund.name}: tracking currency change to #{label} could not be completed. #{rates}. " \
       "Tracking figures are partly rebuilt; add the rates and use Retry on the fund page.", "danger"]
    else
      fund.release_tracking_currency_change!(claim: @claim)
      ["#{fund.name}: tracking currency change to #{label} aborted, nothing was changed. #{rates}", "danger"]
    end
  end

  # Saved through the model (not update_column) so the audit trail records the old and new value
  # against the person who asked, rather than the job. Skipped on a retry that failed after this
  # step, so the audit trail holds one change, not one per attempt.
  def save_tracking_currency(fund, new_currency, user_id)
    return if fund.tracking_currency.presence == new_currency

    Audited.audit_class.as_user(User.find(user_id)) do
      fund.update!(tracking_currency: new_currency)
    end
  end

  def rebuild_tracking_amounts(fund, user_id)
    tracking_job = TrackingCurrencyJob.new
    Audited.audit_class.as_user("ChangeTrackingCurrencyJob") do
      Chewy.strategy(:sidekiq) do
        # has_tracking_currency? is false for a blank tracking currency and for one equal to the
        # fund currency; either way the old tracking figures must not survive under the new label.
        if fund.reload.has_tracking_currency?
          errors = tracking_job.rebuild_fund(fund, user_id)
          # A missing rate is rescued per date inside TrackingCurrencyJob, so a partial rebuild comes
          # back as data, not an exception. Rates were validated above, so this means something
          # changed mid-run (e.g. a rate deleted) - treat it as a failure, not a success.
          raise "some tracking amounts could not be rebuilt: #{errors.to_json}" if errors.present?
        else
          tracking_job.clear_tracking_amounts(fund)
        end
      end
    end
  end
end
