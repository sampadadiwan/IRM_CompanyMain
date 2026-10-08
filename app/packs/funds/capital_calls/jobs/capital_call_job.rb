class CapitalCallJob < ApplicationJob
  # This job can generate multiple capital remittances, which cause deadlocks. Hence serial process these jobs
  queue_as :serial
  attr_accessor :remittances, :payments

  # ── Live progress on the call page while remittances are generated ──────────────────────────
  # Large calls take minutes, so open call pages get a "Generating remittances… 1,240 of 5,000" line
  # and see the rows arrive, and the user who started it gets a notice when it is done. Two throttles
  # keep this cheap however big the call is:
  #   * the progress line (one small rendered string over the cable, no DB work in the browser) is
  #     sent at most every progress_interval;
  #   * the remittances list (every open browser re-runs the paginated index query) is reloaded at
  #     most every list_reload_interval, and only if rows were created since the last reload.
  # class_attributes so tests can set them to 0.
  class_attribute :progress_interval, default: 2.seconds
  class_attribute :list_reload_interval, default: 15.seconds

  # This is idempotent, we should be able to call it multiple times for the same CapitalCall
  # triggered_by_user_id is optional so a job enqueued before this argument existed still runs.
  def perform(capital_call_id, type, triggered_by_user_id = nil)
    @remittances = []
    @payments = []
    Chewy.strategy(:sidekiq) do
      case type
      when "Generate"
        generate(capital_call_id)
      when "Notify"
        notify(capital_call_id, triggered_by_user_id)
      end
    end
    # Real-time journey progress (no-op without a journey). Worked examples J2.2 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
    CapitalCall.find_by(id: capital_call_id)&.journey_progress!(actor: User.find_by(id: triggered_by_user_id))
  end

  def generate(capital_call_id)
    @capital_call = CapitalCall.find(capital_call_id)

    # Some calls are for specific fund closes - so only generate remittances for the commitments in that close
    capital_commitments = @capital_call.applicable_to.includes(:investor, :investor_kyc)

    # One count up front: the "of N" in the progress line and the completion notice
    start_progress(capital_commitments.count)
    Rails.logger.debug { "######## applicable_to record count = #{@progress[:total]}" }

    # find_each: a call over thousands of commitments is walked in batches instead of loaded whole
    capital_commitments.find_each do |capital_commitment|
      # Check if we alread have a CapitalRemittance for this commitment
      Rails.logger.debug { "CapitalCallJob: Creating CapitalRemittance for #{capital_commitment.investor_name} for #{@capital_call.name}" }

      if CapitalRemittance.exists?(capital_call: @capital_call, capital_commitment:)
        Rails.logger.debug { "Skipping remittances for #{capital_commitment}, already present" }
        @progress[:present] += 1
      else

        # Note the due amount for the call is calculated automatically inside CapitalRemittance
        status = @capital_call.generate_remittances_verified ? "Paid" : "Pending"
        cr = CapitalRemittance.new(capital_call: @capital_call, fund: @capital_call.fund,
                                   entity: @capital_call.entity, investor: capital_commitment.investor, capital_commitment:, folio_id: capital_commitment.folio_id,
                                   created_by: "Call",
                                   status:, verified: @capital_call.generate_remittances_verified)

        cr.payment_date = @capital_call.due_date if cr.verified
        # Skip the counter culture updates to avoid deadlocks
        CapitalRemittance.skip_counter_culture_updates do
          result = CapitalRemittanceCreate.call(capital_remittance: cr)
          if result.failure?
            Rails.logger.error { "Error creating CapitalRemittance for #{capital_commitment.investor_name} id #{capital_commitment.id}, #{cr.errors.full_messages}" }
            @progress[:failed] += 1
          else
            @progress[:created] += 1
          end
        end
      end

      # Tell open call pages how far we are (throttled — see report_progress)
      report_progress
    end

    # Generate any payments for the imported remittances if required
    generate_remittance_payments

    # Fix the counters. Passing the call id makes that job refresh this call's stats cards on any
    # open page once the totals are right (they are stale until then — see CapitalCall#broadcast_stats_change)
    CapitalRemittancesCountersJob.perform_later([@capital_call.fund_id], nil, @capital_call.id)
    @progress[:completed] = true
  ensure
    # In ensure so a run that fails partway still clears the progress line, shows the rows it did
    # create and tells the user it stopped. @capital_call is nil if the find failed.
    finish_progress if @capital_call
  end

  def generate_remittance_payments
    # Some rows will be verified but will have no payments, for these generate the payments also
    @capital_call.reload.capital_remittances.verified.each do |cr|
      next unless cr.collected_amount_cents.zero?

      # skip the counter culture updates to avoid deadlocks
      CapitalRemittancePayment.skip_counter_culture_updates do
        crp = CapitalRemittancePayment.new(capital_remittance: cr, fund_id: cr.fund_id, entity_id: cr.entity_id, amount_cents: cr.call_amount_cents, folio_amount_cents: cr.folio_call_amount_cents, payment_date: @capital_call.due_date)

        result = CapitalRemittancePaymentCreate.call(capital_remittance_payment: crp)
        Rails.logger.error { "Error creating CapitalRemittancePayment for CapitalRemitttance - Investor #{cr.investor_name} - Commitment id #{cr.capital_commitment_id}, #{cr.errors.full_messages}" } if result.failure?
      end
    end

    # Fix the counters
    CapitalRemittancePayment.counter_culture_fix_counts where: { fund_id: @capital_call.fund_id }

    # We also need to fix the status of the CapitalRemittances, as the payments will have been created
    @capital_call.capital_remittances.each do |capital_remittance|
      CapitalRemittanceUpdate.call(capital_remittance:)
    end
  end

  def notify(capital_call_id, triggered_by_user_id = nil)
    @capital_call = CapitalCall.find(capital_call_id)

    # Nothing would be sent at all in these cases, so there is nothing to preflight and
    # nothing to alert about — checked before the guard so a disabled or unapproved call
    # never emails "notices not sent" to the admins.
    return unless @capital_call.approved && @capital_call.send_call_notice_flag

    # Preload all associations accessed by send_notification and skip_call_notice? to avoid N+1
    remittances = @capital_call.capital_remittances.includes(:capital_commitment, :capital_call, { investor: :approved_users }, :fund)

    # Size-check before sending any of them, so an oversized attachment stops the whole run
    # instead of bouncing investor by investor at the receiving mail servers. Scoped to the
    # remittances this run would actually email — an oversized document on one already
    # notified must not block first-time notices for the rest of the call. Returns rather than
    # raises: a raise here would just have Sidekiq retry the same doomed batch.
    return if blocked_by_attachment_size?(remittances.where(notification_sent: [false, nil]),
                                          @capital_call.custom_notification(:notify_capital_remittance),
                                          "Cannot send call notices for #{@capital_call.name}", @capital_call.entity_id,
                                          user_id: triggered_by_user_id)

    remittances.find_each do |cr|
      cr.send_notification unless cr.capital_commitment.skip_doc_gen? || cr.notification_sent
    end
  end

  # true when the batch must not go out. CapitalCall#reminder_capital_call performs the same
  # check inline rather than calling this — it lives on the model, not the job — so the two
  # must be kept in step by hand. The part that actually matters (the rule, the message and
  # the reporting) is shared via NotificationAttachmentPreflight; only the wiring is duplicated.
  def blocked_by_attachment_size?(records, custom_notification, context, entity_id, user_id: nil)
    # skip_doc_gen? is not expressible in SQL — it reads a json_fields key — so it is filtered
    # here rather than scoped into the relation.
    skip_doc_gen = ->(cr) { cr.capital_commitment.skip_doc_gen? }

    message = NotificationAttachmentPreflight.batch_error_message(
      records, custom_notification, context:, skip_if: skip_doc_gen
    ) { |record| NotificationAttachmentPreflight.auto_attached_documents(record) }
    return false if message.blank?

    NotificationAttachmentPreflight.report_blocked_send(message, entity_id:, user_id:,
                                                                 subject: "Capital call notices not sent")
    true
  end

  private

  # Counters for this run. The throttle clocks start now, so a call that finishes inside the first
  # interval never flashes a progress line at all — it just gets the final reload and notice.
  def start_progress(total)
    now = monotonic_now
    @progress = { total:, created: 0, present: 0, failed: 0, completed: false,
                  progress_sent_at: now, list_reloaded_at: now, created_at_reload: 0 }
  end

  # Called after each commitment; cheap when nothing is due (two clock comparisons)
  def report_progress
    now = monotonic_now
    done = @progress[:created] + @progress[:present] + @progress[:failed]

    # The progress line, also kept in the cache so a page opened mid-run can show it
    if now - @progress[:progress_sent_at] >= progress_interval.to_f
      @capital_call.broadcast_remittance_progress(done:, total: @progress[:total])
      @progress[:progress_sent_at] = now
    end

    # The list, only when new rows exist to show
    return unless @progress[:created] > @progress[:created_at_reload] && now - @progress[:list_reloaded_at] >= list_reload_interval.to_f

    @capital_call.broadcast_remittances_change
    @progress[:list_reloaded_at] = now
    @progress[:created_at_reload] = @progress[:created]
  end

  # End of the run, however it ended: drop the progress line, reload the list one last time and
  # tell the user who started it
  def finish_progress
    @capital_call.clear_remittance_progress
    @capital_call.broadcast_remittances_change
    notify_generation_finished if @progress
  end

  # An alert on whatever page the user who created / edited / approved the call is on (UserAlert
  # via send_notification). acting_user is captured when the job is enqueued (ApplicationJob);
  # without one (console run, job enqueued before this shipped) send_notification does nothing.
  # The call name is escaped: the alert partial renders the message as HTML.
  def notify_generation_finished
    name = ERB::Util.html_escape(@capital_call.name)
    created, present, failed, total = @progress.values_at(:created, :present, :failed, :total)

    message, level =
      if !@progress[:completed]
        # The job raised — the error itself goes to ExceptionNotifier with the job failure
        done = created + present + failed
        ["Remittance generation for #{name} stopped after #{done} of #{total}.", "danger"]
      elsif failed.positive?
        ["#{name}: #{created + present} of #{total} remittances created, #{failed} failed. Check the call's remittances.", "warning"]
      else
        already = present.positive? ? ", #{present} already present" : ""
        ["Remittances generated for #{name}: #{created} created#{already}.", "info"]
      end

    send_notification(message, acting_user&.id, level)
  rescue StandardError => e
    # A notice must never mask the job's own outcome
    Rails.logger.error("CapitalCallJob notice for CapitalCall##{@capital_call.id} failed: #{e.class} #{e.message}")
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
