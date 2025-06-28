class AllocationsController < ApplicationController
  before_action :set_allocation, only: %i[show edit update destroy verify accept_spa generate_docs]
  after_action :verify_policy_scoped, only: []

  # GET /allocations
  def index
    fetch_rows
    @pagy, @allocations = pagy(@allocations) unless params[:format] == "xlsx"

    if params[:secondary_sale_id].present?
      @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
      @bread_crumbs = { Secondaries: secondary_sales_path,
                        "#{@secondary_sale.name}": secondary_sale_path(@secondary_sale) }
    end
  end

  def fetch_rows
    @q = Allocation.ransack(params[:q])

    # We have to get the offer_id and interest_id from the params, as they are not part of the ransack search
    params[:offer_id] || get_q_param(:offer_id)
    params[:interest_id] || get_q_param(:interest_id)

    # if offer_id.present?
    #   # We have to find the offer and check if we are authorized to view it
    #   @offer = Offer.find(offer_id)
    #   authorize @offer, :show?
    #   @allocations = @q.result.where(offer_id:).verified
    # elsif interest_id.present?
    #   # We have to find the interest and check if we are authorized to view it
    #   @interest = Interest.find(interest_id)
    #   authorize @interest, :show?
    #   @allocations = @q.result.where(interest_id:).verified
    # else
    # If we are not searching by offer_id or interest_id, we can just use policy_scope
    @allocations = policy_scope(@q.result)
    # end

    @allocations = @allocations.where(secondary_sale_id: params[:secondary_sale_id]) if params[:secondary_sale_id].present?

    @allocations = @allocations.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?

    @allocations = @allocations.where(verified: params[:verified]) if params[:verified].present?

    @allocations = @allocations.includes(:entity, :secondary_sale, offer: :investor, interest: :investor)
    @allocations
  end

  # GET /allocations/1
  def show; end

  # GET /allocations/new
  def new
    @allocation = Allocation.new(allocation_params)
    @allocation.entity_id = current_user.entity_id
    authorize @allocation
  end

  # GET /allocations/1/edit
  def edit; end

  # POST /allocations
  def create
    @allocation = Allocation.new(allocation_params)
    @allocation.entity_id = current_user.entity_id
    authorize @allocation
    @allocation = Allocation.build_from(@allocation.offer, @allocation.interest, @allocation.quantity, @allocation.price)
    if @allocation.save
      redirect_to allocations_path(filter: true, secondary_sale_id: @allocation.secondary_sale_id), notice: "Allocation was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /allocations/1
  def update
    if @allocation.update(allocation_params)
      redirect_to allocations_path(filter: true, secondary_sale_id: @allocation.secondary_sale_id), notice: "Allocation was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def verify
    success = @allocation.update(verified: !@allocation.verified)
    notice = success ? "Allocation was successfully updated." : "Error: #{@allocation.errors.full_messages}"
    respond_to do |format|
      format.html { redirect_to allocation_url(@allocation), notice: }
      format.json { @allocation.to_json }
    end
  end

  def accept_spa
    result = OfferAcceptSpa.call(allocation: @allocation, current_user:)
    notice = result.success? ? "Offer was successfully updated. Your acceptance has been recorded" : "Error: #{result[:errors]}"
    respond_to do |format|
      format.html { redirect_to allocation_url(@allocation, display_status: true), notice: }
      format.json { @allocation.to_json }
    end
  end

  def generate_docs
    AllocationSpaJob.perform_later(@allocation.secondary_sale_id, @allocation.id, current_user.id, template_id: params[:template_id])
    redirect_to allocation_path(@allocation), notice: "Documentation generation started, please check back in a few mins."
  end

  # DELETE /allocations/1
  def destroy
    @allocation.destroy!
    redirect_to allocations_url, notice: "Allocation was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_allocation
    @allocation = Allocation.find(params[:id])
    authorize @allocation

    @bread_crumbs = { Secondaries: secondary_sales_path,
                      "#{@allocation.secondary_sale.name}": secondary_sale_path(@allocation.secondary_sale) }
  end

  # Only allow a list of trusted parameters through.
  def allocation_params
    params.require(:allocation).permit(:offer_id, :interest_id, :secondary_sale_id, :entity_id, :quantity, :price, :amount, :notes, :verified)
  end
end
