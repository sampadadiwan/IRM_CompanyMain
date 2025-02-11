class DealsController < ApplicationController
  include DealsHelper
  before_action :set_deal, only: %w[show update destroy edit overview consolidated_access_rights]
  after_action :verify_authorized, except: %i[index search investor_deals]

  # GET /deals or /deals.json
  def index
    @deals = policy_scope(Deal)
    @bread_crumbs = { Deals: deals_path }
    @deals = @deals.where("deals.archived=?", false) if params[:include_archived].blank?
    @units = params[:units]
  end

  def search
    @entity = current_user.entity
    query = params[:query]
    if query.present?
      @deals = DealIndex.filter(term: { entity_id: @entity.id })
                        .query(query_string: { fields: DealIndex::SEARCH_FIELDS,
                                               query:, default_operator: 'and' }).objects
    else
      redirect_to deals_path
    end

    render "index"
  end

  def investor_deals
    @deals = Deal.for_investor(current_user)
    @deals = @deals.page params[:page]
    render "index"
  end

  def consolidated_access_rights
    @access_rights = policy_scope(AccessRight).includes(:owner, :investor, :user)

    @bread_crumbs['Access Overview'] = nil
    @deal_documents_folder = @deal.deal_documents_folder

    @access_rights = @access_rights.where(owner_id: @deal.id, owner_type: "Deal").or(@access_rights.where(owner_id: @deal_documents_folder.id, owner_type: "Folder"))
    query = params[:search][:value] if params[:search] && params[:search][:value].present?
    if query.present?
      ids = AccessRightIndex.filter(term: { entity_id: current_user.entity_id })
                            .query(query_string: { fields: AccessRightIndex::SEARCH_FIELDS,
                                                   query:, default_operator: 'and' }).per(100).map(&:id)

      @access_rights = @access_rights.where(id: ids)
    end
    @access_rights = @access_rights.order(owner_type: :asc, created_at: :desc)
    @grouped_access_rights = get_grouped_access_rights(@access_rights)

    @grouped_access_rights = filter_by_owner(@grouped_access_rights, params[:access])
    if params[:all].blank?
      @grouped_access_rights = Kaminari.paginate_array(@grouped_access_rights.to_a).page(params[:page])
      params[:per_page] ||= 10
      @grouped_access_rights = @grouped_access_rights.per(params[:per_page].to_i)
    end
  end

  # GET /deals/1 or /deals/1.json
  def show
    if params[:chart].present?
      render "deal_charts"
    else
      respond_to do |format|
        format.xlsx do
          @activity_names = %w[Investor Status Primary Secondary Advisor] + DealActivity.templates(@deal)
          response.headers[
            'Content-Disposition'
          ] = "attachment; filename=deal.xlsx"

          render params[:grid_view].present? ? "grid_view" : "show"
        end
        format.html do
          # make board the default view if deal has a board
          if params[:grid_view].present?
            render "grid_view"
          elsif params[:overview].present? || current_user.curr_role_investor?
            redirect_to overview_deal_path(@deal)
          elsif @deal.kanban_board.present?
            redirect_to board_path(@deal.kanban_board)
          else
            render "grid_view"
          end
        end
      end
    end
  end

  def overview; end

  # GET /deals/new
  def new
    @deal = Deal.new(deal_params)
    @deal.currency = @deal.entity.currency
    @deal.activity_list = Deal::ACTIVITIES
    @deal.start_date = Time.zone.today

    authorize @deal
    setup_custom_fields(@deal)
  end

  # GET /deals/1/edit
  def edit
    setup_custom_fields(@deal)
    if params[:turbo]
      frame = params[:turbo_frame_id] || "deal_form_#{@deal.id}"
      render turbo_stream: [
        turbo_stream.replace(frame, partial: "deals/form", locals: { deal: @deal, turbo_frame_id: frame, turbo: true })
      ]
    end
  end

  # POST /deals or /deals.json
  def create
    @deal = Deal.new(deal_params)
    @deal.entity_id = current_user.entity_id
    authorize @deal

    results = CreateDeal.wtf?(deal: @deal)
    respond_to do |format|
      if results.success?
        format.html { redirect_to deal_url(@deal, kanban: true), notice: "Deal was successfully created." }
        format.json { render :show, status: :created, location: @deal }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @deal.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /deals/1 or /deals/1.json
  def update
    @frame = params[:deal][:turbo_frame_id] || "deal_form_#{@deal.id}"
    params[:deal].delete(:turbo_frame_id)
    @deal.assign_attributes(deal_params)
    respond_to do |format|
      if UpdateDeal.wtf?(deal: @deal).success?
        @success = true
        format.turbo_stream do
          UserAlert.new(user_id: current_user.id, message: "Deal was successfully updated! Please refresh!", level: "success").broadcast
          render :update
        end
        format.html { redirect_to deal_url(@deal, kanban: true), notice: "Deal was successfully updated." }
        format.json { render :show, status: :ok, location: @deal }
      else
        @success = false
        @alert = "Deal could not be updated! #{@deal.errors.full_messages.join(', ')}"
        format.turbo_stream { render :update }
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @deal.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /deals/1 or /deals/1.json
  def destroy
    @deal.destroy

    respond_to do |format|
      format.html { redirect_to deals_url, notice: "Deal was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_deal
    @deal = Deal.find(params[:id])
    deals_path = deal_investors_path if current_user.curr_role_investor?
    path = if current_user.curr_role_investor?
             overview_deal_path(@deal)
           else
             deal_path(@deal)
           end
    @bread_crumbs = { Deals: deals_path, "#{@deal.name || '-'}": path }
    authorize(@deal)
  end

  # Only allow a list of trusted parameters through.
  def deal_params
    params.require(:deal).permit(:entity_id, :name, :amount, :status, :form_type_id, :clone_from_id, :tags,
                                 :start_date, :currency, :units, :activity_list, :archived, card_view_attrs: [], properties: {})
  end
end
