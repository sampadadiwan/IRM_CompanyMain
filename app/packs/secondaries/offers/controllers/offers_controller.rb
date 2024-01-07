class OffersController < ApplicationController
  before_action :set_offer, only: %i[show edit update destroy approve allocate allocation_form accept_spa]
  after_action :verify_authorized, except: %i[index search finalize_allocation]

  # GET /offers or /offers.json
  def index
    # Default to policy
    @offers = policy_scope(Offer)

    @offers = @offers.where(approved: params[:approved] == "true") if params[:approved].present?
    @offers = @offers.where(verified: params[:verified]) if params[:verified].present?
    @offers = @offers.where(secondary_sale_id: params[:secondary_sale_id]) if params[:secondary_sale_id].present?
    @offers = @offers.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
    @offers = @offers.joins(:investor, :user).includes(:secondary_sale, :entity, :interest, holding: :funding_round)

    @offers = @offers.page(params[:page]) unless request.format.xlsx? || params[:all] == 'true'

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

      if params[:finalize_allocation].present?
        if params[:secondary_sale_id].present?
          render "/offers/finalize_allocation"
        elsif params[:interest_id].present?
          render "/interests/matched_offers"
        else
          render "index"
        end
      else
        render "index"
      end

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

  def accept_spa
    @offer.final_agreement = true
    @offer.final_agreement_user_id = current_user.id
    @offer.save!
    respond_to do |format|
      format.html { redirect_to offer_url(@offer, display_status: true), notice: "Offer was successfully updated. Your acceptance has been recorded" }
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
        format.turbo_stream do
          @offer.comments = "Error: #{@offer.errors.full_messages}"
          render turbo_stream: [
            turbo_stream.replace("tf_offer_#{@offer.id}", partial: "offers/final_offer", locals: { offer: @offer })
          ]
        end
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

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_offer
    @offer = Offer.find(params[:id])
    authorize @offer
  end

  # Only allow a list of trusted parameters through.
  def offer_params
    params.require(:offer).permit(:user_id, :entity_id, :secondary_sale_id, :investor_id,
                                  :holding_id, :quantity, :percentage, :notes, :full_name, :PAN, :address, :bank_account_number, :bank_name, :ifsc_code, :city, :demat,
                                  :comments, :verified, :interest_id, :form_type_id, :allocation_quantity,
                                  :acquirer_name, :bank_routing_info, :id_proof, :address_proof, :spa, :signature, :pan_card, docs_uploaded_check: {}, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
