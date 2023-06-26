class InterestsController < ApplicationController
  before_action :set_interest, only: %i[show edit update destroy short_list finalize allocate
                                        allocation_form matched_offers accept_spa]

  # GET /interests or /interests.json
  def index
    @interests = policy_scope(Interest).includes(:entity, :interest_entity, :user)
    @secondary_sale = nil
    if params[:secondary_sale_id].present?
      @interests = @interests.where(secondary_sale_id: params[:secondary_sale_id])
      @interests = @interests.order(allocation_quantity: :desc)
      @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    end

    # @interests = @interests.page(params[:page]).per(params[:per_page] || 10)

    render "index"
  end

  def matched_offers
    @offers = @interest.offers
    @offers = @offers.where(approved: params[:approved] == "true") if params[:approved].present?
    @offers = @offers.where(verified: params[:verified]) if params[:verified].present?
    @offers = @offers.includes(:user, :investor, :secondary_sale, :entity, :interest).page(params[:page])
  end

  # GET /interests/1 or /interests/1.json
  def show; end

  # GET /interests/new
  def new
    @interest = Interest.new(interest_params)
    @interest.user_id ||= current_user.id
    @interest.interest_entity_id ||= @interest.investor&.investor_entity_id || current_user.entity_id
    @interest.entity_id = @interest.secondary_sale.entity_id
    @interest.price = @interest.secondary_sale.final_price if @interest.secondary_sale.price_type == "Fixed Price"
    setup_custom_fields(@interest)
    authorize @interest
  end

  # GET /interests/1/edit
  def edit
    setup_custom_fields(@interest)
  end

  # POST /interests or /interests.json
  def create
    @interest = Interest.new(interest_params)
    @interest.user_id ||= current_user.id
    @interest.interest_entity_id ||= @interest.investor&.investor_entity_id || current_user.entity_id
    @interest.entity_id = @interest.secondary_sale.entity_id
    authorize @interest

    setup_doc_user(@interest)

    respond_to do |format|
      if @interest.save
        format.html { redirect_to interest_url(@interest), notice: "Interest was successfully created." }
        format.json { render :show, status: :created, location: @interest }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @interest.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /interests/1 or /interests/1.json
  def update
    setup_doc_user(@interest)

    respond_to do |format|
      if @interest.update(interest_params)
        format.html { redirect_to interest_url(@interest), notice: "Interest was successfully updated." }
        format.json { render :show, status: :ok, location: @interest }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @interest.errors, status: :unprocessable_entity }
      end
    end
  end

  def allocate
    @interest.allocation_quantity = interest_params[:allocation_quantity]
    @interest.comments = interest_params[:comments]
    @interest.verified = interest_params[:verified]

    respond_to do |format|
      if @interest.save
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("tf_interest_#{@interest.id}", partial: "interests/final_interest", locals: { interest: @interest })
          ]
        end
        format.html { redirect_to interest_url(@interest), notice: "Interest was successfully updated." }
        format.json { render :show, status: :ok, location: @interest }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @interest.errors, status: :unprocessable_entity }
      end
    end
  end

  def allocation_form; end

  def short_list
    @interest.short_listed = !@interest.short_listed
    @interest.save!

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(@interest, partial: "interests/interest",
                                          locals: { interest: @interest, secondary_sale: @interest.secondary_sale })
        ]
      end
      format.html { redirect_to interest_url(@interest), notice: "Interest was successfully shortlisted." }
      format.json { @interest.to_json }
    end
  end

  def accept_spa
    @interest.final_agreement = true
    @interest.final_agreement_user = current_user

    respond_to do |format|
      if @interest.save
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(@interest, partial: "interests/interest",
                                            locals: { interest: @interest, secondary_sale: @interest.secondary_sale })
          ]
        end
        format.html { redirect_to interest_url(@interest), notice: "Interest was successfully updated." }
        format.json { @interest.to_json }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @interest.errors, status: :unprocessable_entity }
      end
    end
  end

  def finalize
    @interest.finalized = true
    @interest.save
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(@interest, partial: "interests/interest",
                                          locals: { interest: @interest, secondary_sale: @interest.secondary_sale })
        ]
      end
      format.html { redirect_to interest_url(@interest), notice: "Interest was successfully marked as final." }
      format.json { @interest.to_json }
    end
  end

  # DELETE /interests/1 or /interests/1.json
  def destroy
    @interest.destroy

    respond_to do |format|
      format.html { redirect_to interests_url, notice: "Interest was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_interest
    @interest = Interest.find(params[:id])
    authorize @interest
  end

  # Only allow a list of trusted parameters through.
  def interest_params
    params.require(:interest).permit(:entity_id, :quantity, :price, :user_id, :verified,
                                     :comments, :escrow_deposited, :details, :allocation_quantity,
                                     :investor_id, :secondary_sale_id, :buyer_entity_name,
                                     :demat, :city, :bank_account_number, :ifsc_code, :form_type_id,
                                     :address, :contact_name, :email, :PAN, :final_agreement, :signature,
                                     documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
