class InvestorAccessesController < ApplicationController
  before_action :set_investor_access, only: %i[show edit update destroy approve]
  after_action :verify_authorized, except: %i[index search]

  # GET /investor_accesses or /investor_accesses.json
  def index
    authorize(InvestorAccess)
    @q = InvestorAccess.ransack(params[:q])
    @investor_accesses = policy_scope(@q.result).includes(:investor, :user, :granter)
    @investor_accesses = InvestorAccessSearch.perform(@investor_accesses, current_user, params)
    @investor_accesses = @investor_accesses.where(approved: params[:approved]) if params[:approved].present?
    @investor_accesses = @investor_accesses.where(investor_id: params[:investor_id]) if params[:investor_id].present?
    @investor_accesses = @investor_accesses.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
    @pagy, @investor_accesses = pagy(@investor_accesses) if params[:all].blank?
  end

  def search
    @entity = current_user.entity
    query = params[:query]
    if query.present?

      InvestorAccessIndex.filter(term: { entity_id: @entity.id })
                         .query(query_string: { fields: InvestorAccessIndex::SEARCH_FIELDS,
                                                query:, default_operator: 'and' }).objects

      render "index"
    else
      redirect_to investor_accesses_path
    end
  end

  def request_access
    @investor_access = InvestorAccess.new(investor_access_params)
    @investor_access.user_id = current_user.id
    @investor_access.email = current_user.email
    @investor_access.first_name = current_user.first_name
    @investor_access.last_name = current_user.last_name
    @investor_access.entity_id = @investor_access.investor.entity_id
    @investor_access.approved = false
    authorize @investor_access

    respond_to do |format|
      if @investor_access.save
        format.html { redirect_to entity_path(@investor_access.entity), notice: "Investor access request successfull. You will be notified when your request is approved." }
        format.json { render :show, status: :created, location: @investor_access }
      else
        format.html { redirect_to entity_path(@investor_access.entity), notice: "Investor access request failed. #{@investor_access.errors.full_messages}" }
        format.json { render json: @investor_access.errors, status: :unprocessable_entity }
      end
    end
  end

  # GET /investor_accesses/1 or /investor_accesses/1.json
  def show; end

  # GET /investor_accesses/new
  def new
    @investor_access = InvestorAccess.new(investor_access_params)
    @investor_access.approved = true
    @investor_access.send_confirmation = true

    authorize @investor_access
  end

  # GET /investor_accesses/1/edit
  def edit; end

  def approve
    @investor_access.approved = !@investor_access.approved
    @investor_access.granted_by = current_user.id
    @investor_access.save
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(@investor_access)
        ]
      end
      format.html { redirect_to investor_access_path(@investor_access), notice: "Investor access was successfully approved." }
      format.json { @investor_access.to_json }
    end
  end

  def upload; end

  # POST /investor_accesses or /investor_accesses.json
  def create
    @investor_access = InvestorAccess.new(investor_access_params)
    @investor_access.entity_id = @investor_access.investor.entity_id
    @investor_access.granted_by = current_user.id

    authorize @investor_access

    respond_to do |format|
      if @investor_access.save
        format.turbo_stream { render :create }
        format.html { redirect_to investor_access_path(@investor_access), notice: "Investor access was successfully created." }
        format.json { render :show, status: :created, location: @investor_access }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor_access.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investor_accesses/1 or /investor_accesses/1.json
  def update
    authorize @investor_access

    respond_to do |format|
      if @investor_access.update(investor_access_params)
        format.turbo_stream { render :update }
        format.html { redirect_to investor_access_path(@investor_access), notice: "Investor access was successfully updated." }
        format.json { render :show, status: :ok, location: @investor_access }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investor_access.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investor_accesses/1 or /investor_accesses/1.json
  def destroy
    @investor_access.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(@investor_access)
        ]
      end
      format.html { redirect_to investor_accesses_path, notice: "Investor access was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_investor_access
    @investor_access = InvestorAccess.includes(:user).find(params[:id])
    authorize @investor_access
  end

  # Only allow a list of trusted parameters through.
  def investor_access_params
    params.require(:investor_access).permit(:investor_id, :user_id, :email, :cc, :approved, :send_confirmation,
                                            :phone, :whatsapp_enabled, :granted_by, :entity_id, :first_name, :last_name, :call_code, :email_enabled)
  end
end
