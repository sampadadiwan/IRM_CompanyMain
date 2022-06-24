class SecondarySalesController < ApplicationController
  before_action :set_secondary_sale, only: %i[show edit update destroy make_visible download allocate
                                              notify_allocation spa_upload lock_allocations ]

  after_action :verify_policy_scoped, only: []

  # GET /secondary_sales or /secondary_sales.json
  def index
    @secondary_sales = policy_scope(SecondarySale)
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
    @secondary_sale.percent_allowed = 100
    setup_custom_fields(@secondary_sale)
    authorize @secondary_sale
  end

  # GET /secondary_sales/1/edit
  def edit
    setup_custom_fields(@secondary_sale)
  end

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

  def lock_allocations
    @secondary_sale.lock_allocations = !@secondary_sale.lock_allocations
    @secondary_sale.finalized = !@secondary_sale.finalized

    label = @secondary_sale.lock_allocations ? "Locked" : "Unlocked"
    respond_to do |format|
      if @secondary_sale.save
        format.html do
          redirect_to finalize_allocation_offers_path(secondary_sale_id: @secondary_sale.id),
                      notice: "Allocations are now #{label}."
        end

        format.json { render :show, status: :created, location: @secondary_sale }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @secondary_sale.errors, status: :unprocessable_entity }
      end
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

    setup_doc_user(@secondary_sale)

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
  end

  # Only allow a list of trusted parameters through.
  def secondary_sale_params
    params.require(:secondary_sale).permit(:name, :entity_id, :start_date, :end_date, :final_price, :form_type_id,
                                           :percent_allowed, :min_price, :max_price, :active, :price_type,
                                           :seller_doc_list, :finalized, :spa, :final_allocation, :spa_template,
                                           seller_instructions: [], private_docs: [], public_docs: [], buyer_instructions: [], properties: {},
                                           documents_attributes: Document::NESTED_ATTRIBUTES)
  end
end
