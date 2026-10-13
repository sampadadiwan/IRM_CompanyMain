# Order book (GP), subscribe / redeem wizards (investors), admin entry, cancel and journey actions.
# Worked examples H7–H15, E13–E20, X10–X16, X19 — openspec/changes/open-ended-funds/design.md#worked-examples
module Evergreen
  class OrdersController < BaseController
    include WithJourneyPanel

    before_action :require_evergreen!
    before_action :set_order, only: %i[show cancel accept reject verify_signatory upload_form record_payment accept_received]

    # Filter dropdown on the order book: key => statuses (nil = every status)
    ORDER_FILTERS = { "open" => DealingOrder::OPEN_STATUSES, "dealt" => %w[dealt], "closed" => %w[cancelled rejected], "all" => nil }.freeze

    def index
      authorize DealingOrder.new(fund: @fund, entity_id: @fund.entity_id), :index?
      @orders = policy_scope(DealingOrder).where(fund_id: @fund.id).includes(:investor, :capital_commitment, :dealing_date, :dealing_fills)
      @orders = @orders.where(kind: params[:kind]) if DealingOrder::KINDS.include?(params[:kind])
      # Finished orders are hidden unless asked for: the list opens on what is still waiting to be dealt
      # (an explicit ?status= link still works, against every status)
      @filter = if ORDER_FILTERS.key?(params[:filter])
                  params[:filter]
                elsif DealingOrder::STATUSES.include?(params[:status])
                  "all"
                else
                  "open"
                end
      @orders = @orders.where(status: ORDER_FILTERS[@filter]) if ORDER_FILTERS[@filter]
      @orders = @orders.where(status: params[:status]) if DealingOrder::STATUSES.include?(params[:status])
      # Open orders read in the order they will be dealt — dealing date, then queue (first received
      # first) — so the gate's running total grows down the page; history reads newest first
      @orders = if @filter == "open"
                  @orders.joins(:dealing_date).order("dealing_dates.date ASC, dealing_orders.received_at ASC, dealing_orders.id ASC")
                else
                  @orders.order(received_at: :desc)
                end
      @pagy, @orders = pagy(@orders, limit: 50)
      # Latest approved NAV per class: the Amount / Units estimate for the side the investor didn't ask in
      @navs = @fund.unit_types_list.index_with { |ut| FundNav.latest_approved(@fund, ut, Time.zone.today) }
      # The gate forecast runs over every open redemption, not just this page, so paging never drops one
      @queue = DealingOrder.where(fund_id: @fund.id, kind: "redemption", status: DealingOrder::OPEN_STATUSES)
                           .includes(:investor, :dealing_date, :dealing_fills).in_queue_order
      # What the gate does to each queued redemption, shown on the request's own row (GP only)
      @gate = EvergreenGateForecast.call(@fund, @queue) if gp_user? && params[:kind] != "subscription"
    end

    def show
      authorize @order
      @journey = evaluate_journey(@order) if @order.workflow_instances.exists?
    end

    # Pre-funded money arriving before the dealing date (walkthrough rows 4–5): record + verify
    def record_payment
      authorize @order, :record_payment?
      ok, error = EvergreenPayments.record_subscription_payment(@order.capital_remittance, amount: params[:amount], payment_date: params[:payment_date],
                                                                                           reference: params[:reference], user: current_user)
      redirect_back_or_to evergreen_order_path(@fund, @order), **(ok ? { notice: "Payment recorded" } : { alert: error })
    end

    # Accept the money received as the whole subscription (§ Accept received amount)
    def accept_received
      authorize @order
      result = EvergreenAcceptReceived.call(order: @order, current_user:)
      redirect_back_or_to evergreen_order_path(@fund, @order),
                          **(result.success? ? { notice: "Subscription reduced to the amount received" } : { alert: result[:errors] })
    end

    # The investor's signed subscription form (order journey step 2), stored on the investor
    # PDF, images or a Word copy of the signed form
    UPLOAD_TYPES = %w[application/pdf image/png image/jpeg application/msword
                      application/vnd.openxmlformats-officedocument.wordprocessingml.document].freeze

    def upload_form
      authorize @order, :upload_form?
      file = params[:file]
      return redirect_to(evergreen_order_path(@fund, @order), alert: "Choose a PDF, image or Word copy of the signed form") unless file.respond_to?(:content_type) && UPLOAD_TYPES.include?(file.content_type)

      document = Document.new(owner: @order.investor, name: @order.subscription_form_name, owner_tag: "Subscription Form",
                              file:, user_id: current_user.id, entity_id: @order.entity_id)
      return redirect_to(evergreen_order_path(@fund, @order), alert: document.errors.full_messages.to_sentence) unless document.save

      @order.journey_progress!(actor: current_user)
      redirect_to evergreen_order_path(@fund, @order), notice: "Signed form uploaded"
    end

    # Wizard step ①: kind=subscription|redemption
    def new
      @order = build_order
      authorize @order, :create?
    end

    # Indicative units / value, dealing date and queue position, without saving (Turbo Stream)
    def preview
      @order = build_order
      authorize @order, :preview?
      @preview = EvergreenOrderPreview.new(@order)
      render turbo_stream: turbo_stream.replace("order_preview", partial: "evergreen/orders/preview", locals: { order: @order, preview: @preview })
    end

    def create
      @order = build_order
      authorize @order, :create?
      result = DealingOrderCreate.call(fund: @fund, params: order_params.merge(investor_id: @order.investor_id),
                                       current_user:, source: gp_user? ? "admin" : "portal")
      if result.success?
        @order = result[:order]
        render :done
      else
        @error = result[:errors]
        flash.now[:alert] = @error
        render :new, status: :unprocessable_entity
      end
    end

    def cancel
      authorize @order
      result = DealingOrderCancel.call(order: @order, current_user:)
      redirect_back_or_to evergreen_order_path(@fund, @order), **(result.success? ? { notice: "Request cancelled" } : { alert: result[:errors] })
    end

    # Order journey actions (US-14)
    def accept
      authorize @order
      @order.update!(accepted_by: current_user, accepted_at: Time.current)
      @order.journey_progress!(actor: current_user) if @order.respond_to?(:journey_progress!)
      redirect_to evergreen_order_path(@fund, @order), notice: "Order accepted"
    end

    def reject
      authorize @order
      result = DealingOrderCancel.call(order: @order, current_user:, reason: params[:reason].to_s.strip.truncate(255).presence || "Rejected", status: "rejected")
      redirect_to evergreen_order_path(@fund, @order), result.success? ? { notice: "Order rejected" } : { alert: result[:errors] }
    end

    def verify_signatory
      authorize @order
      return redirect_to(evergreen_order_path(@fund, @order), notice: "Signatory already verified") if @order.signatory_verified_at

      @order.update!(signatory_verified_by: current_user, signatory_verified_at: Time.current)
      @order.journey_progress!(actor: current_user) if @order.respond_to?(:journey_progress!)
      redirect_to evergreen_order_path(@fund, @order), notice: "Signatory verified"
    end

    private

    def set_order
      @order = @fund.dealing_orders.find(params[:id])
    end

    def order_params
      # investor_kyc_id: the investing entity; OrderEligibility accepts only the investor's approved KYCs (X3)
      permitted = %i[kind unit_type amount units all_units note capital_commitment_id investor_kyc_id]
      permitted += %i[investor_id received_at folio_id] if gp_user?
      attrs = params.fetch(:dealing_order, {}).permit(*permitted).to_h
      unless gp_user?
        # Investors may only name their own folio of this fund
        own = InvestorAccess.approved_for_user(current_user).where(entity_id: @fund.entity_id).pluck(:investor_id)
        attrs["capital_commitment_id"] = @fund.capital_commitments.where(investor_id: own).find_by(id: attrs["capital_commitment_id"])&.id
      end
      attrs
    end

    # Investors order for themselves: their single investor of this fund's entity, else the folio's
    def build_order
      attrs = order_params
      investor_id = if gp_user?
                      attrs[:investor_id].presence || @fund.capital_commitments.find_by(id: attrs[:capital_commitment_id])&.investor_id
                    else
                      own = InvestorAccess.approved_for_user(current_user).where(entity_id: @fund.entity_id).pluck(:investor_id)
                      folio = @fund.capital_commitments.where(investor_id: own).find_by(id: attrs[:capital_commitment_id])
                      folio&.investor_id || own.first
                    end
      DealingOrder.new(entity_id: @fund.entity_id, fund: @fund, investor_id:, kind: attrs[:kind].presence || params[:kind] || "subscription",
                       unit_type: attrs[:unit_type].presence || @fund.unit_types_list.first,
                       capital_commitment_id: @fund.capital_commitments.find_by(id: attrs[:capital_commitment_id])&.id,
                       investor_kyc_id: attrs[:investor_kyc_id].presence,
                       amount_cents: attrs[:amount].presence && (attrs[:amount].to_s.delete(",").to_d * 100),
                       units: attrs[:units].presence&.to_s&.delete(",")&.to_d,
                       all_units: ActiveModel::Type::Boolean.new.cast(attrs[:all_units]) || false,
                       received_at: Time.current)
    end
  end
end
