class SecondarySalesController < ApplicationController
  before_action :set_secondary_sale, only: %i[show edit update destroy make_visible download allocate notify_allocation spa_upload]
  after_action :verify_policy_scoped, only: []

  # GET /secondary_sales or /secondary_sales.json
  def index
    @secondary_sales = if current_user.has_cached_role?(:holding)
                         SecondarySale.none
                       else
                         policy_scope(SecondarySale)
                       end
  end

  def search
    @entity = current_user.entity

    query = params[:query]
    if query.present?
      @secondary_sales = if current_user.has_role?(:super)

                           SecondarySaleIndex.query(query_string: { fields: SecondarySaleIndex::SEARCH_FIELDS,
                                                                    query:, default_operator: 'and' }).objects

                         else
                           SecondarySaleIndex.filter(term: { entity_id: @entity.id })
                                             .query(query_string: { fields: SecondarySaleIndex::SEARCH_FIELDS,
                                                                    query:, default_operator: 'and' }).objects
                         end

    end
    render "index"
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
    @secondary_sale.percent_allowed = 100
    authorize @secondary_sale
  end

  # GET /secondary_sales/1/edit
  def edit; end

  def spa_upload; end

  def make_visible
    @secondary_sale.visible_externally = !@secondary_sale.visible_externally
    @secondary_sale.notify_advisors if @secondary_sale.visible_externally

    respond_to do |format|
      if @secondary_sale.save
        format.html { redirect_to secondary_sale_url(@secondary_sale), notice: "Secondary sale was successfully updated." }
        format.json { render :show, status: :created, location: @secondary_sale }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @secondary_sale.errors, status: :unprocessable_entity }
      end
    end
  end

  def allocate
    AllocationJob.perform_later(@secondary_sale.id)
    respond_to do |format|
      format.html { redirect_to secondary_sale_url(@secondary_sale), notice: "Allocation in progress, checkback in a few minutes. Please use the Dowload button once allocation is complete." }
      format.json { render :show, status: :ok, location: @secondary_sale }
    end
  end

  def notify_allocation
    @secondary_sale.notify_allocation
    respond_to do |format|
      format.html { redirect_to secondary_sale_url(@secondary_sale), notice: "Allocation notification sent successfully." }
      format.json { render :show, status: :ok, location: @secondary_sale }
    end
  end

  # POST /secondary_sales or /secondary_sales.json
  def create
    @secondary_sale = SecondarySale.new(secondary_sale_params)
    @secondary_sale.entity_id = current_user.entity_id
    authorize @secondary_sale

    respond_to do |format|
      if @secondary_sale.save
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
    @secondary_sale = SecondarySale.with_attached_public_docs.find(params[:id])
    authorize @secondary_sale
  end

  # Only allow a list of trusted parameters through.
  def secondary_sale_params
    params.require(:secondary_sale).permit(:name, :entity_id, :start_date, :end_date, :final_price,
                                           :percent_allowed, :min_price, :max_price, :active, :price_type,
                                           :seller_doc_list, :finalized, :spa, :final_allocation,
                                           seller_instructions: [], private_docs: [], public_docs: [], buyer_instructions: [])
  end
end
