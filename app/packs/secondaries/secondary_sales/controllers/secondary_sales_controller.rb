class SecondarySalesController < ApplicationController
  before_action :set_secondary_sale,
                only: %i[show edit update destroy make_visible download allocate
                         send_notification offers interests payments approve_offers short_list_interests generate_spa report]

  after_action :verify_policy_scoped, only: []

  # GET /secondary_sales or /secondary_sales.json
  def index
    authorize(SecondarySale)
    @q = SecondarySale.ransack(params[:q])
    @secondary_sales = policy_scope(@q.result).includes(:entity)
  end

  def offers
    @q = @secondary_sale.offers.ransack(params[:q])
    @offers = policy_scope(@q.result)
    @offers = @offers.includes(:user, :investor, :secondary_sale, :entity, :documents)

    @offers = OfferSearchService.perform(@offers, current_user, params)
    if !request.format.xlsx? && params[:all].blank?
      page = params[:page] || 1
      @offers = @offers.page(page)
      @offers = @offers.per(params[:per_page].to_i) if params[:per_page].present?
    end

    if params[:report]
      render "/offers/#{params[:report]}"
    else
      render "/offers/index"
    end
  end

  def interests
    @q = @secondary_sale.interests.ransack(params[:q])
    @interests = policy_scope(@q.result).includes(:entity, :interest_entity, :user, :investor)
    @interests = @interests.where(interest_entity_id: current_user.entity_id) unless policy(@secondary_sale).owner? || policy(@secondary_sale).rm?

    # @interests = @interests.eligible(@secondary_sale) if params[:eligible].present? && params[:eligible] == "true"
    # @interests = @interests.not_eligible(@secondary_sale) if params[:eligible].present? && params[:eligible] == "false"

    @interests = @interests.short_listed if params[:short_listed].present? && params[:short_listed] == "true"
    @interests = @interests.not_short_listed if params[:short_listed].present? && params[:short_listed] == "false"

    @interest = @interests.pending if params[:short_listed_status] == "pending"
    @interest = @interests.rejected if params[:short_listed_status] == "rejected"
    @interest = @interests.short_listed if params[:short_listed_status] == "short_listed"

    @interests = @interests.where(signature_data: nil) if params[:signature] == 'false'
    @interests = @interests.where(final_agreement: false) if params[:final_agreement] == 'false'

    @interests = @interests.page(params[:page]) unless request.format.xlsx?

    if params[:report]
      render "/interests/#{params[:report]}"
    else
      render "/interests/index"
    end
  end

  def approve_offers
    errors = []
    success = 0
    @offers = @secondary_sale.offers.where(approved: false)
    @offers.each do |offer|
      result = OfferApprove.call(offer:, current_user:)
      if result.success?
        success += 1
      else
        errors << "Offer: #{offer.id} #{result[:errors]}"
      end
    end

    notice = errors.empty? ? "Approved all pending offers" : "Approved #{success},  <br>Errors:<br> #{errors.join('<br>')}"

    redirect_to secondary_sale_url(@secondary_sale), notice:
  end

  def short_list_interests
    errors = []
    success = 0
    @interests = @secondary_sale.interests.pending
    @interests.each do |interest|
      result = InterestShortList.call(interest:, current_user:, short_listed_status: Interest::STATUS_SHORT_LISTED)
      if result.success?
        success += 1
      else
        errors << "Interest: #{interest.id} #{result[:errors]}"
      end
    end

    notice = errors.empty? ? "Shortlisted all pending interests" : "Shortlisted #{success},  <br>Errors:<br> #{errors.join('<br>')}"

    redirect_to secondary_sale_url(@secondary_sale), notice:
  end

  def payments
    @fees = @secondary_sale.fees

    @offers = @secondary_sale.offers.approved.matched
    @offers = @offers.verified if params[:verified] == 'true'

    @offers = @offers.includes(:user, :investor, :secondary_sale, :entity, :interest).order("interests.buyer_entity_name")

    @buyer_offers = Offer.compute_payments(@offers, @fees)

    respond_to do |format|
      format.xlsx do
        response.headers[
          'Content-Disposition'
        ] = "attachment; filename=payments.xlsx"
      end
      format.html { render :payments }
      format.json { render :index }
    end
  end

  def search
    @entity = current_user.entity

    query = params[:query]
    if query.present?
      @secondary_sales = SecondarySaleIndex.filter(term: { entity_id: @entity.id })
                                           .query(query_string: { fields: SecondarySaleIndex::SEARCH_FIELDS,
                                                                  query:, default_operator: 'and' }).objects

      render "index"
    else
      redirect_to secondary_sales_path
    end
  end

  def download
    authorize @secondary_sale
  end

  # GET /secondary_sales/1 or /secondary_sales/1.json
  def show; end

  # GET /secondary_sales/new
  def new
    @secondary_sale = SecondarySale.new(secondary_sale_params)
    @secondary_sale.entity_id = current_user.entity_id
    @secondary_sale.start_date = Time.zone.today
    @secondary_sale.end_date = Time.zone.today + 2.weeks
    @secondary_sale.offer_end_date = Time.zone.today + 1.week
    @secondary_sale.percent_allowed = 100
    setup_custom_fields(@secondary_sale, force_form_type: @secondary_sale.secondary_sale_form_type)
    authorize @secondary_sale
  end

  # GET /secondary_sales/1/edit
  def edit
    setup_custom_fields(@secondary_sale, force_form_type: @secondary_sale.secondary_sale_form_type)
  end

  def allocate
    if request.method == "POST"
      priority = params[:priority]
      matching_priority = params[:matching_priority]
      NewAllocationJob.perform_later(@secondary_sale.id, current_user.id,
                                     params[:allocation_engine], priority:, matching_priority:)

      respond_to do |format|
        format.html { redirect_to secondary_sale_url(@secondary_sale), notice: "Allocation in progress, checkback in a few minutes." }
        format.json { render :show, status: :ok, location: @secondary_sale }
      end
    elsif request.method == "GET"
      render "pick_allocation_engine"
    end
  end

  def report
    render "secondary_sales/#{params[:report]}"
  end

  def generate_spa
    # Post the allocation, we need to upload the SPAs for verified offers

    if params[:offer_doc_generation].present?
      OfferSpaJob.perform_later(@secondary_sale.id, nil, current_user.id, template_id: params[:template_id])
    elsif params[:interest_doc_generation].present?
      InterestDocJob.perform_later(@secondary_sale.id, nil, current_user.id, template_id: params[:template_id])
    else
      notice = "No document generation selected"
    end

    notice ||= "Document generation in progress, checkback in a few minutes."

    respond_to do |format|
      format.html { redirect_to secondary_sale_url(@secondary_sale), notice: }
      format.json { render :show, status: :ok, location: @secondary_sale }
    end
  end

  def send_notification
    if SecondarySale::NOTIFICATIONS.include? params[:notification]
      if params[:notification] == "adhoc_notification"
        @secondary_sale.send(params[:notification], params[:notification_id])
      else
        @secondary_sale.send(params[:notification])
      end
    end
    respond_to do |format|
      format.html { redirect_to secondary_sale_url(@secondary_sale), notice: "Notification sent successfully." }
      format.json { render :show, status: :ok, location: @secondary_sale }
    end
  end

  # POST /secondary_sales or /secondary_sales.json
  def create
    @secondary_sale = SecondarySale.new(secondary_sale_params)
    @secondary_sale.entity_id = current_user.entity_id
    authorize @secondary_sale

    setup_doc_user(@secondary_sale)
    result = SecondarySaleCreate.call(secondary_sale: @secondary_sale, current_user:)
    respond_to do |format|
      if result.success?
        format.html { redirect_to secondary_sale_url(@secondary_sale), notice: "Secondary sale was successfully created." }
        format.json { render :show, status: :created, location: @secondary_sale }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @secondary_sale.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /secondary_sales/1 or /secondary_sales/1.json
  def update
    setup_doc_user(@secondary_sale)

    respond_to do |format|
      if @secondary_sale.update(secondary_sale_params)
        format.html { redirect_to secondary_sale_url(@secondary_sale), notice: "Secondary sale was successfully updated." }
        format.json { render :show, status: :ok, location: @secondary_sale }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @secondary_sale.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /secondary_sales/1 or /secondary_sales/1.json
  def destroy
    @secondary_sale.destroy

    respond_to do |format|
      format.html { redirect_to secondary_sales_url, notice: "Secondary sale was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_secondary_sale
    @secondary_sale = SecondarySale.find(params[:id])
    authorize @secondary_sale

    @bread_crumbs = { Secondaries: secondary_sales_path,
                      "#{@secondary_sale.name}": secondary_sale_path(@secondary_sale) }
  end

  # Only allow a list of trusted parameters through.
  def secondary_sale_params
    params.require(:secondary_sale).permit(:name, :entity_id, :start_date, :end_date, :final_price, :form_type_id, :percent_allowed, :min_price, :max_price, :active, :price_type, :seller_doc_list, :finalized, :spa, :offer_end_date, :support_email, :buyer_doc_list, :indicative_quantity, :show_quantity, :interest_form_type_id, :interest_pivot_custom_fields, :offer_form_type_id, :offer_pivot_custom_fields, notification_employee_ids: [], seller_instructions: [], private_docs: [], public_docs: [], buyer_instructions: [], properties: {}, documents_attributes: Document::NESTED_ATTRIBUTES)
  end
end
