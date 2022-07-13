class OffersController < ApplicationController
  before_action :set_offer, only: %i[show edit update destroy approve allocate allocation_form]
  after_action :verify_authorized, except: %i[index search finalize_allocation]

  # GET /offers or /offers.json
  def index
    # Default to policy
    @offers = policy_scope(Offer)

    @offers = @offers.where(approved: params[:approved] == "true") if params[:approved].present?
    @offers = @offers.where(verified: params[:verified]) if params[:verified].present?
    @offers = @offers.where(secondary_sale_id: params[:secondary_sale_id]) if params[:secondary_sale_id].present?
    @offers = @offers.includes(:user, :investor, :secondary_sale, :entity, :interest)
    @offers = @offers.page(params[:page])

    render "index"
  end

  def finalize_allocation
    @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    if @secondary_sale.entity_id == current_user.entity_id
      @offers = policy_scope(Offer)
      @offers = @offers.where(secondary_sale_id: params[:secondary_sale_id])
    else
      # This is a shortlisted interest. Show offers allocated to it
      @interest = @secondary_sale.interests.short_listed.where(interest_entity_id: current_user.entity_id).first
      @offers = if @interest
                  @interest.offers
                else
                  # Default to policy
                  policy_scope(Offer)
                end
    end

    @offers = @offers.where(approved: params[:approved] == "true") if params[:approved].present?
    @offers = @offers.where(verified: params[:verified]) if params[:verified].present?
    @offers = @offers.includes(:user, :investor, :secondary_sale, :entity, :interest).page(params[:page])

    render "finalize_allocation"
  end

  def search
    @entity = current_user.entity
    query = params[:query]

    if query.present?

      if params[:secondary_sale_id].present?
        @secondary_sale_id = params[:secondary_sale_id].to_i
        @secondary_sale = SecondarySale.find(params[:secondary_sale_id])

        if @secondary_sale.entity_id == current_user.entity_id
          term = { secondary_sale_id: @secondary_sale_id }
        else
          # This is a shortlisted interest. Show offers allocated to it
          @interest = @secondary_sale.interests.short_listed.where(interest_entity_id: current_user.entity_id).first
          term = { interest_id: @interest.id }
        end
      else
        term = { entity_id: @entity.id }
      end

      @offers = OfferIndex.filter(term:)
                          .query(query_string: { fields: OfferIndex::SEARCH_FIELDS,
                                                 query:, default_operator: 'and' }).page(params[:page]).objects

      render params[:finalize_allocation].present? ? "finalize_allocation" : "index"

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
    @offer.first_name = current_user.first_name
    @offer.last_name = current_user.last_name
    @offer.entity_id = @offer.secondary_sale.entity_id
    @offer.quantity = @offer.allowed_quantity
    setup_custom_fields(@offer)

    authorize @offer
  end

  def approve
    @offer.approved = !@offer.approved
    label = @offer.approved ? "approved" : "unapproved"
    @offer.granted_by_user_id = current_user.id
    @offer.save!
    respond_to do |format|
      format.html { redirect_to offer_url(@offer), notice: "Offer was successfully #{label}." }
      format.json { @offer.to_json }
    end
  end

  # GET /offers/1/edit
  def edit
    setup_custom_fields(@offer)
  end

  def allocate
    @offer.allocation_quantity = offer_params[:allocation_quantity]
    @offer.comments = offer_params[:comments]
    @offer.verified = offer_params[:verified]
    @offer.interest_id = offer_params[:interest_id]

    respond_to do |format|
      if @offer.save
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("tf_offer_#{@offer.id}", partial: "offers/final_offer", locals: { offer: @offer })
          ]
        end
        format.html { redirect_to offer_url(@offer), notice: "Offer was successfully updated." }
        format.json { render :show, status: :ok, location: @offer }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @offer.errors, status: :unprocessable_entity }
      end
    end
  end

  def allocation_form; end

  # POST /offers or /offers.json
  def create
    @offer = Offer.new(offer_params)
    @offer.user_id = current_user.id
    @offer.entity_id = @offer.secondary_sale.entity_id

    authorize @offer
    setup_doc_user(@offer)

    respond_to do |format|
      if @offer.save
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
    setup_doc_user(@offer)

    respond_to do |format|
      if @offer.update(offer_params)
        format.html { redirect_to offer_url(@offer), notice: "Offer was successfully updated." }
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

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_offer
    @offer = Offer.find(params[:id])
    authorize @offer
  end

  # Only allow a list of trusted parameters through.
  def offer_params
    params.require(:offer).permit(:user_id, :entity_id, :secondary_sale_id, :investor_id,
                                  :holding_id, :quantity, :percentage, :notes, :first_name, :last_name,
                                  :middle_name, :PAN, :address, :bank_account_number, :bank_name,
                                  :comments, :verified, :final_agreement, :interest_id, :form_type_id,
                                  :allocation_quantity, :acquirer_name, :bank_routing_info, :id_proof, :address_proof, :spa, :signature, docs_uploaded_check: {},
                                                                                                                                         documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
