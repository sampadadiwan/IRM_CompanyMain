class OffersController < ApplicationController
  before_action :set_offer, only: %i[show edit update destroy approve allocate allocation_form accept_spa generate_docs]
  after_action :verify_authorized, except: %i[index search]

  # GET /offers or /offers.json
  def index
    # Default to policy
    fetch_rows
    respond_to do |format|
      format.xlsx do
        response.headers[
          'Content-Disposition'
        ] = "attachment; filename=offers.xlsx"
      end
      format.html { render :index }
      format.json { render json: OfferDatatable.new(params, offers: @offers) }
    end
  end

  def fetch_rows
    @q = Offer.ransack(params[:q])
    @offers = policy_scope(@q.result).includes(:user, :investor, :secondary_sale)
    @offers = OfferSearchService.new.fetch_rows(@offers, params)
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id]) if params[:secondary_sale_id].present?
    unless request.format.xlsx? || params[:all] == 'true'
      page = params[:page] || 1
      @offers = @offers.page(page)
      @offers = @offers.per(params[:per_page].to_i) if params[:per_page].present?
    end
    authorize(Offer)
    @offers
  end

  def search_term
    if params[:secondary_sale_id].present?
      @secondary_sale_id = params[:secondary_sale_id].to_i
      @secondary_sale = SecondarySale.find(params[:secondary_sale_id])

      term = { secondary_sale_id: @secondary_sale_id } if @secondary_sale.entity_id == current_user.entity_id
    elsif params[:interest_id].present?
      @interest = Interest.find(params[:interest_id])
      authorize @interest, :show?
      term = { interest_id: @interest.id }
    else
      term = { entity_id: @entity.id }
    end

    term
  end

  def search
    @entity = current_user.entity
    query = params[:query]

    if query.present?

      @offers = OfferIndex.filter(term: search_term)
                          .query(query_string: { fields: OfferIndex::SEARCH_FIELDS,
                                                 query:, default_operator: 'and' }).page(params[:page]).objects

      render "index"

    else
      redirect_to offers_path(request.parameters)
    end
  end

  # GET /offers/1 or /offers/1.json
  def show; end

  # GET /offers/new
  def new
    @offer = Offer.new(offer_params)
    @offer.user_id = current_user.id
    @offer.full_name = current_user.full_name
    @offer.entity_id = @offer.secondary_sale.entity_id
    @offer.investor_id ||= @offer.entity.investors.where(investor_entity_id: current_user.entity_id).first&.id
    setup_custom_fields(@offer, force_form_type: @offer.secondary_sale.offer_form_type)

    authorize @offer
  end

  def approve
    result = OfferApprove.call(offer: @offer, current_user:)
    label = result[:label]
    notice = result.success? ? "Offer was successfully #{label}." : "Error: #{result[:errors]}"
    respond_to do |format|
      format.html { redirect_to offer_url(@offer), notice: }
      format.json { @offer.to_json }
    end
  end

  def accept_spa
    result = OfferAcceptSpa.call(offer: @offer, current_user:)
    notice = result.success? ? "Offer was successfully updated. Your acceptance has been recorded" : "Error: #{result[:errors]}"
    respond_to do |format|
      format.html { redirect_to offer_url(@offer, display_status: true), notice: }
      format.json { @offer.to_json }
    end
  end

  # GET /offers/1/edit
  def edit
    setup_custom_fields(@offer, force_form_type: @offer.secondary_sale.offer_form_type)
  end

  # POST /offers or /offers.json
  def create
    @offer = Offer.new(offer_params)
    authorize @offer
    setup_doc_user(@offer)
    result = OfferCreate.call(offer: @offer, current_user:)
    respond_to do |format|
      if result.success?
        format.html { redirect_to offer_url(@offer), notice: "Offer was successfully created." }
        format.json { render :show, status: :created, location: @offer }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @offer.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /offers/1 or /offers/1.json
  def update
    @offer.assign_attributes(offer_params)
    setup_doc_user(@offer)
    result = OfferUpdate.call(offer: @offer, current_user:)
    respond_to do |format|
      if result.success?
        format.html { redirect_to offer_url(@offer, display_status: true), notice: "Offer was successfully updated. You will be notified on next steps." }
        format.json { render :show, status: :ok, location: @offer }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @offer.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /offers/1 or /offers/1.json
  def destroy
    @offer.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(@offer)
        ]
      end
      format.html { redirect_to offers_url, notice: "Offer was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def generate_docs
    OfferSpaJob.perform_later(@offer.secondary_sale_id, @offer.id, current_user.id, template_id: params[:template_id])
    redirect_to offer_path(@offer), notice: "Documentation generation started, please check back in a few mins."
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_offer
    @offer = Offer.find(params[:id])
    authorize @offer
    @bread_crumbs = { Secondaries: secondary_sales_path,
                      "#{@offer.secondary_sale.name}": offers_secondary_sale_path(@offer.secondary_sale),
                      "#{@offer}": nil }
  end

  # Only allow a list of trusted parameters through.
  def offer_params
    params.require(:offer).permit(:user_id, :entity_id, :secondary_sale_id, :investor_id, :price, :completed, :quantity, :percentage, :notes, :full_name, :PAN, :address, :bank_account_number, :bank_name, :ifsc_code, :city, :demat, :comments, :verified, :interest_id, :form_type_id, :allocation_quantity, :acquirer_name, :bank_routing_info, :id_proof, :address_proof, :spa, :seller_signatory_emails, docs_uploaded_check: {}, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
