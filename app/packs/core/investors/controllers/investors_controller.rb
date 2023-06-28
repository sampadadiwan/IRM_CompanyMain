class InvestorsController < ApplicationController
  before_action :set_investor, only: %w[show update destroy edit]
  after_action :verify_authorized, except: [:merge]

  # GET /investors or /investors.json
  def index
    @investors = policy_scope(Investor).joins(:entity)
    authorize(Investor)
    @investors = @investors.where(category: params[:category]) if params[:category]

    if params[:search] && params[:search][:value].present?
      # This is only when the datatable sends a search query
      query = "#{params[:search][:value]}*"

      ids = InvestorIndex.filter(terms: { _id: @investors.pluck(:id) })
                         .query(query_string: { fields: InvestorIndex::SEARCH_FIELDS,
                                                query:, default_operator: 'and' }).map(&:id)

      @investors = Investor.where(id: ids)
    end

    @investors = @investors.page(params[:page]) if params[:all].blank?
    respond_to do |format|
      format.html
      format.turbo_stream
      format.xlsx
      format.json { render json: InvestorDatatable.new(params, investors: @investors) }
    end
  end

  def merge
    @entity = current_user.has_cached_role?(:super) ? Entity.find(params[:entity_id]) : current_user.entity
    if request.get?
      render "merge"
    else
      old_investor = Investor.find(params[:old_investor_id])
      new_investor = Investor.find(params[:new_investor_id])
      authorize(old_investor, :update?)
      authorize(new_investor, :update?)

      InvestorMergeJob.perform_later(old_investor.id, new_investor.id, current_user.id)
      redirect_to investor_url(new_investor), notice: "Investor merge in progress, please check back in a few mins"
    end
  end

  def search
    query = params[:query]
    if query.present?
      @investors = InvestorIndex.filter(term: { entity_id: current_user.entity_id })
                                .query(query_string: { fields: InvestorIndex::SEARCH_FIELDS,
                                                       query:, default_operator: 'and' }).objects

      render "index"
    else
      redirect_to investors_path
    end
  end

  # GET /investors/1 or /investors/1.json
  def show
    authorize @investor
  end

  # GET /investors/new
  def new
    @investor = Investor.new(investor_params)
    authorize @investor
    setup_custom_fields(@investor)
  end

  # GET /investors/1/edit
  def edit
    authorize @investor
    setup_custom_fields(@investor)
  end

  # POST /investors or /investors.json
  def create
    @investor = Investor.new(investor_params)
    @investor.entity_id = current_user.entity_id
    authorize @investor

    respond_to do |format|
      if @investor.save
        redirect_url = params[:back_to].presence || investor_url(@investor)
        format.html { redirect_to redirect_url, notice: "Investor was successfully created." }
        format.json { render :show, status: :created, location: @investor }
      else
        logger.debug @investor.errors.full_messages

        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investors/1 or /investors/1.json
  def update
    authorize @investor
    respond_to do |format|
      if @investor.update(investor_params)
        format.html { redirect_to investor_url(@investor), notice: "Investor was successfully updated." }
        format.json { render :show, status: :ok, location: @investor }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investor.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investors/1 or /investors/1.json
  def destroy
    authorize @investor
    @investor.destroy

    respond_to do |format|
      format.html { redirect_to investors_url, notice: "Investor was successfully deleted." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investor
    @investor = Investor.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def investor_params
    params.require(:investor).permit(:investor_entity_id, :tag_list, :investor_name, :form_type_id,
                                     :entity_id, :category, :city, properties: {})
  end
end
