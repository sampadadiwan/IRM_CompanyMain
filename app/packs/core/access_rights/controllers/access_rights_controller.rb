class AccessRightsController < ApplicationController
  include AccessRightsHelper

  before_action :set_access_right, only: %w[show update destroy edit]

  # GET /access_rights or /access_rights.json
  def index
    # Step 1: Apply policy scope and eager load associations
    @access_rights = policy_scope(AccessRight).includes(:investor, :user)

    # Step 2: Apply filters if specific deal or investor access is requested
    @access_rights = filter_params(@access_rights, :access_to_investor_id)
    # access_rights.deals returns the rights that have access_type deals, thus filtering out all other ones, so calling it conditionally
    @access_rights = filter_params(@access_rights.deals, :deal_id) if params[:deal_id].present?

    # Step 3: Investor-specific logic
    if params[:investor_id].present?
      # When filtering by investor, apply investor-specific scope
      # This ensures the correct behavior in investor details partial
      investor = Investor.find(params[:investor_id])
      @access_rights = @access_rights.for_investor(investor)
    else
      # Otherwise, include owner-level access rights
      @access_rights = with_owner_access(@access_rights)
    end

    # Step 4: Include soft-deleted records if requested
    @access_rights = @access_rights.with_deleted if params[:with_deleted].present?

    # Step 5: Apply pagination
    @pagy, @access_rights = pagy(@access_rights)
  end

  def search
    @entity = current_user.entity
    @owner = nil
    query = params[:query]
    if params[:owner_type].present? && params[:owner_id].present?
      # Search in fund provided user is authorized
      @owner = params[:owner_type].constantize.find(params[:owner_id])
      authorize(@owner, :show?)
      term = { owner_id: @owner.id, owner_type: params[:owner_type] }
    else
      # Search in users entity only
      term = { entity_id: current_user.entity_id }
    end

    if query.present?
      @access_rights = if @owner
                         AccessRightIndex.filter(term: { owner_id: @owner.id })
                                         .query(match: { owner_type: params[:owner_type] })
                                         .query(query_string: { fields: AccessRightIndex::SEARCH_FIELDS,
                                                                query:, default_operator: 'and' })
                       else
                         AccessRightIndex.filter(term:)
                                         .query(query_string: { fields: AccessRightIndex::SEARCH_FIELDS,
                                                                query:, default_operator: 'and' })
                       end

      @pagy, @access_rights = pagy(@access_rights.page(params[:page]).objects)
      render "index"
    else
      redirect_to access_rights_path(params.to_enum.to_h)
    end
  end

  # GET /access_rights/1 or /access_rights/1.json
  def show
    authorize @access_right
  end

  # GET /access_rights/new
  def new
    @access_right = AccessRight.new(access_right_params)
    authorize @access_right

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.append('new_access_right', partial: "access_rights/form", locals: { access_right: @access_right, partial_to_use: params[:partial_to_use] })
        ]
      end
      format.html
    end
  end

  # GET /access_rights/1/edit
  def edit
    authorize @access_right
  end

  # POST /access_rights or /access_rights.json
  def create
    @access_rights = initialize_from_params(access_right_params)
    @access_rights.each { |access_right| access_right.granted_by = current_user }
    @access_rights.each(&:save)
    @access_rights = AccessRight.includes(:investor, :owner).where(id: @access_rights.collect(&:id))
    @partial_to_use = params[:partial_to_use] || "access_right"
    respond_to do |format|
      format.turbo_stream { render :create }
      format.html { redirect_to access_right_url(@access_right), notice: "Access right was successfully created." }
      format.json { render :show, status: :created, location: @access_right }
    end
  end

  # PATCH/PUT /access_rights/1 or /access_rights/1.json
  def update
    authorize @access_right

    respond_to do |format|
      if @access_right.update(access_right_params)
        format.html { redirect_to access_right_url(@access_right), notice: "Access right was successfully updated." }
        format.json { render :show, status: :ok, location: @access_right }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @access_right.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /access_rights/1 or /access_rights/1.json
  def destroy
    authorize @access_right
    @access_right.destroy
    redirect_to = params[:back_to] || access_rights_url
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove(@access_right)
        ]
      end
      format.html { redirect_to redirect_to, notice: "Access right was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_access_right
    @access_right = AccessRight.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def access_right_params
    params.require(:access_right).permit(:owner_id, :owner_type, :access_type, :metadata, :notify, :tag_list,
                                         :entity_id, :cascade, user_id: [], permissions: [], access_to_category: [], access_to_investor_id: [])
  end
end
