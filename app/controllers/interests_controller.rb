class InterestsController < ApplicationController
  before_action :set_interest, only: %i[show edit update destroy short_list finalize allocate allocation_form]

  # GET /interests or /interests.json
  def index
    @interests = policy_scope(Interest).includes(:interest_entity, :user)

    if params[:secondary_sale_id].present?
      @interests = @interests.where(secondary_sale_id: params[:secondary_sale_id])
      @interests = @interests.order(allocation_quantity: :desc)
      @secondary_sale = SecondarySale.find(params[:secondary_sale_id])
    end

    @interests = @interests.page(params[:page]).per(params[:per_page] || 10)

    render params[:finalize_allocation].present? ? "finalize_allocation" : "index"
  end

  # GET /interests/1 or /interests/1.json
  def show; end

  # GET /interests/new
  def new
    @interest = Interest.new(interest_params)
    @interest.user_id = current_user.id
    @interest.interest_entity_id = current_user.entity_id
    @interest.offer_entity_id = @interest.secondary_sale.entity_id
    @interest.price = @interest.secondary_sale.final_price if @interest.secondary_sale.price_type == "Fixed Price"

    # Custom form fields
    form_type = FormType.where(entity_id: current_user.entity_id, name: "Interest").first
    @interest.form_type = form_type

    authorize @interest
  end

  # GET /interests/1/edit
  def edit; end

  # POST /interests or /interests.json
  def create
    @interest = Interest.new(interest_params)
    @interest.user_id = current_user.id
    @interest.interest_entity_id = current_user.entity_id
    @interest.offer_entity_id = @interest.secondary_sale.entity_id
    authorize @interest

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
    @interest.save

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
    params.require(:interest).permit(:offer_entity_id, :quantity, :price, :user_id, :verified,
                                     :allocation_quantity, :comments,
                                     :interest_entity_id, :secondary_sale_id, :buyer_entity_name,
                                     :address, :contact_name, :email, :PAN, :final_agreement,
                                     buyer_docs: [], properties: {})
  end
end
