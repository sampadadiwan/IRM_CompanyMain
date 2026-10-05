class CapitalDistributionPaymentRecomputeFeesJob < BulkActionJob
  # started_at: when the change that needs this recompute began (the date-change job passes its own);
  # sign-offs given before it are reset if the journey moves back.
  def perform(capital_distribution_id, user_id = nil, started_at: nil)
    started_at ||= Time.current
    # Loaded before the first message so it names the distribution (it used to print a blank name)
    # Worked examples X5 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
    @capital_distribution = CapitalDistribution.find(capital_distribution_id)
    send_notification("Recomputing fees for all payments for distribution #{@capital_distribution}", user_id, :info) if user_id.present?

    @error_msg = []
    processed_count = 0
    Chewy.strategy(:sidekiq) do
      @capital_distribution.capital_distribution_payments.find_each do |capital_distribution_payment|
        CapitalDistributionPaymentUpdate.call(capital_distribution_payment:)
        processed_count += 1
      rescue StandardError => e
        msg = "Error recomputing fees for capital distribution payment #{capital_distribution_payment.id}: #{e.message}"
        send_notification(msg, user_id, :danger) if user_id.present?
        @error_msg << { msg:, folio_id: capital_distribution_payment.folio_id, capital_distribution_payment_id: capital_distribution_payment.id, for: capital_distribution_payment.capital_distribution }
      end
    end

    evaluate_journey(started_at, user_id)

    if @error_msg.present?
      @main_error = "Recompute completed for #{processed_count} records, with #{@error_msg.length} errors"
      msg = "#{@main_error}. Errors will be sent via email"
      send_notification(msg, user_id, :danger) if user_id.present?
      # send notification with errors to user if user_id is present
      send_errors_notification(msg, @error_msg, user_id, :danger) if user_id.present?
      email_errors
    elsif user_id.present?
      send_notification("Recomputed fees for all capital distribution payments successfully for distribution #{@capital_distribution}", user_id, :success)
    end
  end

  private

  # Recomputed fees change the figures on the notices: Generate notices is invalidated (only notices
  # generated afterwards satisfy it — design Decision 11) and the journey is re-checked as an undo,
  # so it moves back and later sign-offs given before started_at are reset. No-op without a journey.
  # Worked examples E8, E15 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def evaluate_journey(started_at, user_id)
    actor = User.find_by(id: user_id)
    notices = Document.where(owner_type: "CapitalDistributionPayment", owner_tag: "Generated",
                             owner_id: @capital_distribution.capital_distribution_payments.select(:id))
    if notices.exists?
      @capital_distribution.journey_invalidate(check_keys: %w[capital_distribution.generate_notices], actor:,
                                               reason: "Fees were recomputed after the notices were generated — unapprove them on the Documents screen, then click Generate Documents")
    end
    @capital_distribution.journey_undo_evaluate(note: "Fees recomputed", started_at:, actor:)
  end
end
