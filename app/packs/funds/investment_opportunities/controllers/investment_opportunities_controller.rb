class InvestmentOpportunitiesController < ApplicationController
  before_action :authenticate_user!, except: %i[no_password_show]
  before_action :set_investment_opportunity, only: %i[show edit update destroy toggle allocate send_notification finalize_allocation]

  skip_after_action :verify_authorized, only: [:no_password_show]
  # GET /investment_opportunities or /investment_opportunities.json
  def index
    authorize(InvestmentOpportunity)
    @investment_opportunities = policy_scope(InvestmentOpportunity)

    @investment_opportunities = @investment_opportunities.where(entity_id: params[:entity_id]) if params[:entity_id].present?
    @investment_opportunities = @investment_opportunities.where("investment_opportunities.tag_list like ?", "%#{params[:tag]}%") if params[:tag].present?
    @pagy, @investment_opportunities = pagy(@investment_opportunities)
  end

  def search
    query = params[:query]
    if query.present?
      @investment_opportunities = InvestmentOpportunityIndex.filter(term: { entity_id: current_user.entity_id })
                                                            .query(query_string: { fields: InvestmentOpportunityIndex::SEARCH_FIELDS,
                                                                                   query:, default_operator: 'and' })

      @pagy, @investment_opportunities = pagy(@investment_opportunities.page(params[:page]).objects)
      render "index"
    else
      redirect_to investment_opportunities_path
    end
  end

  # GET /investment_opportunities/1 or /investment_opportunities/1.json
  def show; end

  # Called when advisors share a link to the IO, the IO is shared without a password
  def no_password_show
    @investment_opportunity = InvestmentOpportunity.find_signed(params[:signed_id], purpose: "shared_by_#{params[:shared_by]}")
    if @investment_opportunity&.shareable
      render "show"
    else
      redirect_to root_path, alert: "You are not authorized to view this page"
    end
  end

  # GET /investment_opportunities/new
  def new
    @investment_opportunity = InvestmentOpportunity.new
    @investment_opportunity.entity_id = current_user.entity_id
    @investment_opportunity.currency = current_user.entity.currency
    @investment_opportunity.last_date = Time.zone.today + 1.month
    authorize @investment_opportunity
    setup_custom_fields(@investment_opportunity)
  end

  # GET /investment_opportunities/1/edit
  def edit
    setup_custom_fields(@investment_opportunity)
  end

  # POST /investment_opportunities or /investment_opportunities.json
  def create
    @investment_opportunity = InvestmentOpportunity.new(investment_opportunity_params)
    authorize(@investment_opportunity)

    respond_to do |format|
      if @investment_opportunity.save
        format.html { redirect_to investment_opportunity_url(@investment_opportunity), notice: "Investment opportunity was successfully created." }
        format.json { render :show, status: :created, location: @investment_opportunity }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investment_opportunity.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investment_opportunities/1 or /investment_opportunities/1.json
  def update
    respond_to do |format|
      if @investment_opportunity.update(investment_opportunity_params)
        format.html { redirect_to investment_opportunity_url(@investment_opportunity), notice: "Investment opportunity was successfully updated." }
        format.json { render :show, status: :ok, location: @investment_opportunity }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investment_opportunity.errors, status: :unprocessable_entity }
      end
    end
  end

  def allocate
    InvestmentOpportunityJob.perform_later(@investment_opportunity.id)

    respond_to do |format|
      format.html { redirect_to investment_opportunity_url(@investment_opportunity), notice: "Allocation in progress, checkback in a few minutes." }
      format.json { render :show, status: :ok, location: @investment_opportunity }
    end
  end

  def toggle
    @investment_opportunity.lock_eoi = !@investment_opportunity.lock_eoi if params[:lock_eoi]
    @investment_opportunity.lock_allocations = !@investment_opportunity.lock_allocations if params[:lock_allocations]
    @investment_opportunity.save

    respond_to do |format|
      format.html { redirect_to investment_opportunity_url(@investment_opportunity), notice: "Investment opportunity was successfully updated." }
      format.json { render :show, status: :ok, location: @investment_opportunity }
    end
  end

  def send_notification
    @investment_opportunity.send(params[:notification]) if %w[notify_open_for_interests notify_allocation].include? params[:notification]
    respond_to do |format|
      format.html { redirect_to investment_opportunity_url(@investment_opportunity), notice: "Notification sent successfully." }
      format.json { render :show, status: :ok, location: @investment_opportunity }
    end
  end

  # DELETE /investment_opportunities/1 or /investment_opportunities/1.json
  def destroy
    @investment_opportunity.destroy

    respond_to do |format|
      format.html { redirect_to investment_opportunities_url, notice: "Investment opportunity was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def finalize_allocation
    @expression_of_interests = policy_scope(@investment_opportunity.expression_of_interests)

    @expression_of_interests = @expression_of_interests.where(approved: params[:approved] == "true") if params[:approved].present?
    @expression_of_interests = @expression_of_interests.where(verified: params[:verified]) if params[:verified].present?
    @expression_of_interests = @expression_of_interests.includes(:user, :eoi_entity, :investment_opportunity, :entity).page(params[:page])

    render "finalize_allocation"
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investment_opportunity
    @investment_opportunity = InvestmentOpportunity.find(params[:id])
    authorize @investment_opportunity
  end

  # Only allow a list of trusted parameters through.
  def investment_opportunity_params
    params.require(:investment_opportunity).permit(:entity_id, :company_name, :fund_raise_amount, :valuation, :min_ticket_size, :last_date, :currency, :logo, :video, :tag_list, :details, :buyer_docs_list, :shareable, :form_type_id, documents_attributes: Document::NESTED_ATTRIBUTES, properties: {})
  end
end
