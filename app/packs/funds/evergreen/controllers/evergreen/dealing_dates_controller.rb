# Dealing list and the dealing-date workspace: step bar, pricing (open), settlement tracker
# (confirmed), confirm / undo / close.
# Worked examples H16–H21, E23–E26, E33, X17, X18, X20 — openspec/changes/open-ended-funds/design.md#worked-examples
module Evergreen
  class DealingDatesController < BaseController
    include WithJourneyPanel

    before_action :require_evergreen!
    before_action :set_dealing_date, only: %i[show confirm undo close generate_documents approve_documents]

    def index
      authorize DealingDate.new(fund: @fund, entity_id: @fund.entity_id), :show?
      recent = @fund.dealing_dates.where(date: (Time.zone.today - 6.months)..)
      # Dates with nothing on them are hidden unless asked for (?filter=all): the calendar generates
      # months of empty future dates that would otherwise push the ones that matter off the page
      @filter = params[:filter] == "all" ? "all" : "active"
      if @filter == "active"
        # Kept: a date with orders (cancelled / rejected don't count) or fills — carried redemptions move
        # their order to the next date, so a dealt date may have only fills — plus a confirmed date still
        # to settle, plus the next date still taking orders (cut-off not passed) even if empty, since new orders land there
        with_orders = DealingOrder.where(fund_id: @fund.id).where.not(status: %w[cancelled rejected]).select(:dealing_date_id)
        with_fills = DealingFill.where(fund_id: @fund.id).select(:dealing_date_id)
        next_open = recent.where(status: "open").where(cutoff_at: Time.current..).order(:date).limit(1).pluck(:id)
        recent = recent.where(id: with_orders).or(recent.where(id: with_fills)).or(recent.where(status: "confirmed")).or(recent.where(id: next_open))
      end
      @dealing_dates = recent.order(date: :desc).limit(50)
      ids = @dealing_dates.map(&:id)
      # An open date counts the orders on it; a confirmed / closed date counts what was dealt on it (its fills),
      # as its page does — a part-filled redemption's order moves on to the next date, its fill stays (F2)
      orders = DealingOrder.where(dealing_date_id: ids).where.not(status: %w[cancelled rejected]).group(:dealing_date_id, :kind)
      fills = DealingFill.where(dealing_date_id: ids).group(:dealing_date_id, :kind)
      @counts = { open: orders.sum(:amount_cents), dealt: fills.sum(:amount_cents) }
      @order_counts = { open: orders.count, dealt: fills.count }
    end

    def show
      authorize @dealing_date
      @journey = evaluate_journey(@dealing_date) if @dealing_date.workflow_instances.exists?
      @pricing = DealingPricer.preview(@dealing_date) if @dealing_date.open?
    end

    def confirm
      authorize @dealing_date
      result = DealingConfirm.call(dealing_date: @dealing_date, current_user:, preview_hash: params[:preview_hash])
      redirect_to evergreen_dealing_date_path(@fund, @dealing_date), result.success? ? { notice: "#{date_label} confirmed" } : { alert: result[:errors] }
    end

    def undo
      authorize @dealing_date
      result = DealingUndo.call(dealing_date: @dealing_date, current_user:)
      redirect_to evergreen_dealing_date_path(@fund, @dealing_date), result.success? ? { notice: "Confirmation undone — the #{EvergreenLabels.lower(date_label)} is open again" } : { alert: result[:errors] }
    end

    # ① Generate documents from the fund's templates (background job; approvers are told when done)
    def generate_documents
      authorize @dealing_date
      count = EvergreenDealingDocuments.to_generate(@dealing_date).size
      orphans = EvergreenDealingDocuments.orphaned(@dealing_date)
      # X29: nothing left at all
      return redirect_to(evergreen_dealing_date_path(@fund, @dealing_date), alert: "Nothing to generate — every settled order already has its document or email") if count.zero? && orphans.empty?

      # X95: only plain emails left (the template was removed after settlement) — send them now
      if count.zero?
        orphans.each { |fill| EvergreenDealingDocuments.send_email(fill) }
        @dealing_date.journey_progress!
        return redirect_to evergreen_dealing_date_path(@fund, @dealing_date), notice: "Emailed #{orphans.size} #{'investor'.pluralize(orphans.size)} without a document — their template was removed"
      end

      EvergreenDocumentsJob.perform_later(@dealing_date.id, current_user.id)
      redirect_to evergreen_dealing_date_path(@fund, @dealing_date), notice: "Generating #{count} #{'document'.pluralize(count)} — you'll be notified when they are ready"
    end

    # ② Approve every generated document and email investors with the PDF attached
    def approve_documents
      authorize @dealing_date
      sent = EvergreenDealingDocuments.approve_and_send(@dealing_date, current_user)
      redirect_to evergreen_dealing_date_path(@fund, @dealing_date),
                  sent.positive? ? { notice: "#{sent} #{'document'.pluralize(sent)} approved and sent" } : { alert: "No documents waiting for approval" }
    end

    def close
      authorize @dealing_date
      result = DealingDateClose.call(dealing_date: @dealing_date, current_user:)
      redirect_to evergreen_dealing_date_path(@fund, @dealing_date), result.success? ? { notice: "#{date_label} closed" } : { alert: result[:errors] }
    end

    private

    # The fund's word for a dealing date ("Dealing date" / "Transaction date") for the flash messages
    def date_label
      EvergreenLabels.t(:transaction_date, fund: @fund)
    end

    def set_dealing_date
      @dealing_date = @fund.dealing_dates.find(params[:id])
    end
  end
end
