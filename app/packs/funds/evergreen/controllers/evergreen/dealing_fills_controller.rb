# Settlement tracker row actions on a confirmed dealing date (proposal GP-3).
# Worked examples H23, H24 — openspec/changes/open-ended-funds/design.md#worked-examples
module Evergreen
  class DealingFillsController < BaseController
    before_action :require_evergreen!
    before_action :set_fill
    # Review fix 5c: nothing more is settled on a closed dealing date (the screen hides these buttons)
    before_action :refuse_when_closed

    def record_payment
      authorize @dealing_date, :update?
      return respond(false, nil, "This fill has no subscription payment") unless @fill.capital_remittance

      ok, error = EvergreenPayments.record_subscription_payment(@fill.capital_remittance, amount: params[:amount], payment_date: params[:payment_date],
                                                                                          reference: params[:reference], user: current_user)
      respond(ok, "Payment recorded", error)
    end

    def verify
      authorize @dealing_date, :update?
      return respond(false, nil, "This fill has no subscription payment") unless @fill.capital_remittance

      ok, error = EvergreenPayments.verify(@fill.capital_remittance, current_user)
      respond(ok, "Payment verified", error)
    end

    def mark_paid
      authorize @dealing_date, :update?
      return respond(false, nil, "This fill has no redemption payment") unless @fill.capital_distribution_payment

      ok, error = EvergreenPayments.mark_redemption_paid(@fill.capital_distribution_payment, payment_date: params[:payment_date], reference: params[:reference])
      respond(ok, "Redemption marked paid", error)
    end

    def resend
      authorize @dealing_date, :update?
      return respond(false, nil, "Nothing sent yet") unless @fill.document_sent_at

      EvergreenNotifier.public_send(EvergreenDealingDocuments.kind(@fill), @fill)
      respond(true, "Sent again", nil)
    end

    # Regenerate one document from its template, only while it is not approved (§ Dealing-date documents)
    def regenerate
      authorize @dealing_date, :generate_documents?
      error = EvergreenDealingDocuments.regenerate(@fill, current_user.id)
      respond(error.nil?, "Document regenerated", error)
    end

    private

    def set_fill
      @dealing_date = @fund.dealing_dates.find(params[:dealing_date_id])
      @fill = @dealing_date.dealing_fills.find(params[:id])
    end

    def refuse_when_closed
      return unless @dealing_date.closed?

      date_word = EvergreenLabels.lower(EvergreenLabels.t(:transaction_date, fund: @fund))
      respond(false, nil, "This #{date_word} is closed — no more settlement actions")
    end

    def respond(ok, notice, error)
      # Back to where the action was clicked (the dealing date, or the order page) — the dealing date otherwise
      redirect_back_or_to evergreen_dealing_date_path(@fund, @dealing_date), **(ok ? { notice: } : { alert: error })
    end
  end
end
