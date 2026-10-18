class AccessRightsController < ApplicationController
  include AccessRightsHelper

  before_action :set_access_right, only: %w[show update destroy edit]

  # GET /access_rights or /access_rights.json
  def index
    if params[:investor_id].present?
      @investor = Investor.find(params[:investor_id])
      @bread_crumbs = { Investors: investors_path, @investor.investor_name => investor_path(@investor), 'Access Rights': nil }
    else
      @bread_crumbs = { 'Access Rights': access_rights_path }
    end

    # Step 1: Apply policy scope
    @access_rights = policy_scope(AccessRight)
    @access_rights = AccessRightSearch.search(@access_rights, params, current_user)
    # Step 2: Apply filters if specific deal or investor access is requested
    @access_rights = filter_params(@access_rights, :owner_type, :owner_id, :user_id, :access_to_investor_id)

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

    # Step 5: Apply pagination — includes here so filters don't strip the eager load
    @pagy, @access_rights = pagy(@access_rights.includes(:investor, :user))
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
    @access_rights.each do |access_right|
      access_right.granted_by = current_user
      # A right on the folder alone grants nothing: Document.for_investor and
      # Folder.for_investor join the child's own access_rights, and only the
      # FolderAccessJob that Folder#access_rights_changed enqueues for cascade=true
      # creates those rows. So folder grants always cascade and the form no longer
      # asks - an unticked box used to leave the stakeholder with a data room they
      # could open and no files inside it.
      access_right.cascade = true if access_right.owner_type == "Folder"
    end
    @access_rights.each(&:save)
    @access_rights = AccessRight.includes(:investor, :owner).where(id: @access_rights.collect(&:id))
    @partial_to_use = params[:partial_to_use] || "access_right"
    respond_to do |format|
      format.turbo_stream { render :create }
      format.html { redirect_to access_right_url(@access_right), notice: "Access right was successfully created." }
      # H32: one request can create several rights; @access_right was never set, so the
      # JSON answer was a 500 after the rows were saved — answer with the rows created
      format.json { render :index, status: :created }
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
    @access_right = AccessRight.includes(:investor, :owner).find(params[:id])
    @bread_crumbs = if @access_right.investor
                      {
                        Investors: investors_path,
                        @access_right.investor.investor_name => investor_path(@access_right.investor),
                        'Access Rights': access_rights_path(investor_id: @access_right.access_to_investor_id),
                        @access_right.owner_type => nil
                      }
                    else
                      { 'Access Rights': access_rights_path, @access_right.owner_type => nil }
                    end
  end

  # Only allow a list of trusted parameters through.
  def access_right_params
    params.require(:access_right).permit(:owner_id, :owner_type, :access_type, :metadata, :notify, :tag_list,
                                         :entity_id, :cascade, user_id: [], permissions: [], access_to_category: [], access_to_investor_id: [])
  end
end
