class OffersController < ApplicationController
  before_action :set_offer, only: %i[show edit update destroy approve allocate allocation_form]
  after_action :verify_authorized, except: %i[index search]

  # GET /offers or /offers.json
  def index
    @offers = policy_scope(Offer).includes(:user, :investor, :secondary_sale, :entity)
    @offers = @offers.where(approved: params[:approved] == "true") if params[:approved].present?
    @offers = @offers.where(verified: params[:verified]) if params[:verified].present?

    if params[:secondary_sale_id].present?
      @offers = @offers.where(secondary_sale_id: params[:secondary_sale_id])
      @offers = @offers.with_attached_docs.with_attached_id_proof.with_attached_signature
      @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    end

    @offers = @offers.page(params[:page]).per(params[:per_page] || 10)

    render params[:finalize_allocation].present? ? "finalize_allocation" : "index"
  end

  def search
    @entity = current_user.entity
    query = params[:query]

    if query.present?

      if params[:secondary_sale_id].present?
        @secondary_sale_id = params[:secondary_sale_id].to_i
        @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
      end

      term = if @secondary_sale_id.present?
               { secondary_sale_id: @secondary_sale_id }
             else
               { entity_id: @entity.id }
             end

      @offers = OfferIndex.filter(term:)
                          .query(query_string: { fields: OfferIndex::SEARCH_FIELDS,
                                                 query:, default_operator: 'and' }).objects

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
  def edit; end

  def allocate
    @offer.allocation_quantity = offer_params[:allocation_quantity]
    @offer.comments = offer_params[:comments]
    @offer.verified = offer_params[:verified]
    @offer.approved = offer_params[:approved]
    @offer.acquirer_name = offer_params[:acquirer_name]

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
                                  :comments, :verified,
                                  :allocation_quantity, :acquirer_name, :bank_routing_info, :id_proof, :address_proof, additional_docs: [], signature: [], docs: [])
  end
end
