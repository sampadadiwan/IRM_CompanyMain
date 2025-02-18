class InterestsController < ApplicationController
  before_action :set_interest, only: %i[show edit update destroy short_list allocate
                                        allocation_form accept_spa generate_docs]

  # GET /interests or /interests.json
  def index
    @q = Interest.ransack(params[:q])
    @interests = policy_scope(@q.result).includes(:entity, :interest_entity, :user, :secondary_sale, :investor)
    @secondary_sale = nil

    if params[:secondary_sale_id].present?
      @secondary_sale = SecondarySale.find(params[:secondary_sale_id])

      @interests = @interests.where(secondary_sale_id: params[:secondary_sale_id])
      @interests = @interests.order(allocation_quantity: :desc)

      @interests = @interests.short_listed if params[:short_listed].present? && params[:short_listed] == "true"
      @interests = @interests.not_short_listed if params[:short_listed].present? && params[:short_listed] == "false"

      @interest = @interests.pending if params[:short_listed_status] == "pending"
      @interest = @interests.rejected if params[:short_listed_status] == "rejected"
      @interest = @interests.short_listed if params[:short_listed_status] == "short_listed"

    end

    @interests = @interests.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?

    @interests = @interests.page(params[:page]) unless request.format.xlsx? || params[:all].present?

    if params[:secondary_sale_id].present?
      @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
      @bread_crumbs = { Secondaries: secondary_sales_path,
                        "#{@secondary_sale.name}": secondary_sale_path(@secondary_sale) }
    end

    render "index"
  end

  # GET /interests/1 or /interests/1.json
  def show; end

  # GET /interests/new
  def new
    @interest = Interest.new(interest_params)
    @interest.user_id ||= current_user.id
    @interest.entity_id = @interest.secondary_sale.entity_id
    # Set the investor id
    @interest.investor_id ||= @interest.entity.investors.where(investor_entity_id: current_user.entity_id).first&.id

    redirect_to secondary_sale_path(@interest.secondary_sale, notice: "Investor not set") if @interest.investor_id.blank?

    @interest.interest_entity_id ||= @interest.investor&.investor_entity_id || current_user.entity_id
    @interest.entity_id = @interest.secondary_sale.entity_id
    @interest.price = @interest.secondary_sale.final_price if @interest.secondary_sale.price_type == "Fixed Price"

    setup_custom_fields(@interest, force_form_type: @interest.secondary_sale.interest_form_type)
    authorize @interest
  end

  # GET /interests/1/edit
  def edit
    setup_custom_fields(@interest, force_form_type: @interest.secondary_sale.interest_form_type)
  end

  # POST /interests or /interests.json
  def create
    @interest = Interest.new(interest_params)
    @interest.user_id ||= current_user.id
    @interest.interest_entity_id ||= @interest.investor&.investor_entity_id || current_user.entity_id
    @interest.entity_id = @interest.secondary_sale.entity_id
    authorize @interest

    setup_doc_user(@interest)
    result = InterestCreate.call(interest: @interest)
    respond_to do |format|
      if result.success?
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
    @interest.assign_attributes(interest_params)
    setup_doc_user(@interest)

    respond_to do |format|
      if InterestUpdate.call(interest: @interest).success?
        format.html { redirect_to interest_url(@interest), notice: "Interest was successfully updated." }
        format.json { render :show, status: :ok, location: @interest }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @interest.errors, status: :unprocessable_entity }
      end
    end
  end

  def allocate
    result = InterestAllocate.call(interest: @interest, interest_params:)

    respond_to do |format|
      if result.success?
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("tf_interest_#{@interest.id}", partial: "interests/final_interest", locals: { interest: @interest })
          ]
        end
        format.html { redirect_to interest_url(@interest), notice: "Interest was successfully updated." }
        format.json { render :show, status: :ok, location: @interest }
      else
        @interest.reload
        @interest.comments = result[:errors]
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("tf_interest_#{@interest.id}", partial: "interests/final_interest", locals: { interest: @interest })
          ]
        end
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @interest.errors, status: :unprocessable_entity }
      end
    end
  end

  def allocation_form; end

  def short_list
    result = InterestShortList.call(
      interest: @interest,
      short_listed_status: params[:short_listed_status],
      current_user:
    )

    respond_to do |format|
      if result.success?
        @interest.reload
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(@interest, partial: "interests/interest",
                                            locals: { interest: @interest, secondary_sale: @interest.secondary_sale })
          ]
        end
        format.html { redirect_to interest_url(@interest), notice: "Interest was successfully shortlisted." }
      else
        format.turbo_stream do
          @interest = @interest.reload
          render turbo_stream: [
            turbo_stream.replace(@interest, partial: "interests/interest",
                                            locals: { interest: @interest, secondary_sale: @interest.secondary_sale })
          ]
        end
        format.html { redirect_to interest_url(@interest), notice: "Failed to shortlist." }
      end
      format.json { @interest.to_json }
    end
  end

  def accept_spa
    result = InterestAcceptSpa.call(interest: @interest, current_user:)
    respond_to do |format|
      if result.success?
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

  # DELETE /interests/1 or /interests/1.json
  def destroy
    @interest.destroy

    respond_to do |format|
      format.html { redirect_to interests_url, notice: "Interest was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def generate_docs
    InterestDocJob.perform_later(@interest.secondary_sale_id, @interest.id, current_user.id, template_id: params[:template_id])
    redirect_to interest_path(@interest), notice: "Documentation generation started, please check back in a few mins."
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_interest
    @interest = Interest.find(params[:id])
    authorize @interest
    @bread_crumbs = { Secondaries: secondary_sales_path,
                      "#{@interest.secondary_sale.name}": secondary_sale_path(@interest.secondary_sale, tab: "interests-tab"),
                      "#{@interest}": nil }
  end

  # Only allow a list of trusted parameters through.
  def interest_params
    params.require(:interest).permit(:entity_id, :quantity, :price, :user_id, :verified, :completed,
                                     :comments, :escrow_deposited, :details, :allocation_quantity,
                                     :investor_id, :secondary_sale_id, :buyer_entity_name,
                                     :demat, :city, :bank_account_number, :ifsc_code, :form_type_id,
                                     :address, :contact_name, :email, :PAN, :final_agreement, :signature, :buyer_signatory_emails, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
