class CapitalCallJob < ApplicationJob
  # This job can generate multiple capital remittances, which cause deadlocks. Hence serial process these jobs
  queue_as :serial
  attr_accessor :remittances, :payments

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

    Rails.logger.debug { "######## applicable_to record count = #{capital_commitments.count}" }

    capital_commitments.each_with_index do |capital_commitment, _idx|
      # Check if we alread have a CapitalRemittance for this commitment
      Rails.logger.debug { "CapitalCallJob: Creating CapitalRemittance for #{capital_commitment.investor_name} for #{@capital_call.name}" }

      if CapitalRemittance.exists?(capital_call: @capital_call, capital_commitment:)
        Rails.logger.debug { "Skipping remittances for #{capital_commitment}, already present" }
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
          Rails.logger.error { "Error creating CapitalRemittance for #{capital_commitment.investor_name} id #{capital_commitment.id}, #{cr.errors.full_messages}" } if result.failure?
        end
      end
    end

    # Generate any payments for the imported remittances if required
    generate_remittance_payments

    # Fix the counters
    CapitalRemittancesCountersJob.perform_later([@capital_call.fund_id], nil)
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
end
