class InvestorAdvisorsController < ApplicationController
  before_action :set_investor_advisor, only: %i[show edit update destroy]
  after_action :verify_authorized, except: %i[index switch]

  # GET /investor_advisors or /investor_advisors.json
  def index
    authorize(InvestorAdvisor)
    @bread_crumbs = { 'Investor Advisors': investor_advisors_path }
    @investor_advisors = policy_scope(InvestorAdvisor).includes(:entity, user: :entity)
    @investor_advisors = @investor_advisors.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
  end

  # GET /investor_advisors/1 or /investor_advisors/1.json
  def show; end

  # GET /investor_advisors/new
  def new
    @investor_advisor = InvestorAdvisor.new(investor_advisor_params)
    authorize(@investor_advisor)
  end

  def new_for_investor
    @investor = Investor.find_by(id: params[:investor_id])
    # Finding 7: Gracefully handle missing investor to prevent nil crash and enumeration oracle.
    if @investor.nil?
      authorize({ investor_advisor: nil, investor: nil }, policy_class: InvestorAdvisorPolicy)
      redirect_to funds_path, alert: "Investor not found."
      return
    end

    @fund = Fund.find_by(id: params[:fund_id])
    # Finding 7: Gracefully handle missing fund to prevent nil crash and enumeration oracle.
    if @fund.nil?
      authorize({ investor_advisor: nil, investor: @investor }, policy_class: InvestorAdvisorPolicy)
      redirect_to funds_path, alert: "Fund not found."
      return
    end

    @investor_advisor = InvestorAdvisor.new(entity_id: @investor.investor_entity_id)
    @entity = @investor_advisor.entity
    # The fund is part of what is authorized (S2): it must belong to the investor's fund company.
    authorize({ investor_advisor: @investor_advisor, investor: @investor, fund: @fund }, policy_class: InvestorAdvisorPolicy)
    @back_to = params[:back_to] || fund_path(@fund)
    @bread_crumbs = { Funds: funds_path,
                      "#{@fund.name}": fund_path(@fund),
                      'New Investor Advisor': nil }

    render :new_for_investor, locals: { investor_id: @investor.id, fund_id: @fund.id, back_to: @back_to }
  end

  # GET /investor_advisors/1/edit
  def edit; end

  def create_for_investor
    @investor = Investor.find(params[:investor_advisor][:investor_id])
    @fund = Fund.find(params[:investor_advisor][:fund_id])
    @entity = @investor.investor_entity
    # The fund is part of what is authorized (S2): it must belong to the investor's fund company.
    authorize({ investor_advisor: InvestorAdvisor.new, investor: @investor, fund: @fund }, policy_class: InvestorAdvisorPolicy)

    @investor_advisor = InvestorAdvisor.new(investor_advisor_params)
    # Finding 1: Force entity_id server-side to match the investor's entity.
    # This prevents IDOR where a user could attempt to link an advisor to an unrelated entity.
    @investor_advisor.entity_id = @investor.investor_entity_id
    @investor_advisor.allowed_roles = ["investor"]
    @investor_advisor.owner_name = @fund.name
    @investor_advisor.permissions = @investor.investor_entity.permissions
    @investor_advisor.extended_permissions = %i[investor_kyc_read investor_read]
    @investor_advisor.created_by = current_user
    @investor_advisor.acting_user = current_user

    ActiveRecord::Base.transaction do
      @result = AddFolioInvestorAdvisor.wtf?(investor_advisor: @investor_advisor, investor: @investor, fund: @fund, params: params)
      # alt is create default IA
      unless @result.success?
        raise ActiveRecord::Rollback # <-- rolls back the transaction without raising an exception outward
      end
    end
    @bread_crumbs = { Funds: funds_path,
                      "#{@fund.name}": fund_path(@fund),
                      'New Investor Advisor': nil }

    @back_to = params[:investor_advisor][:back_to] || fund_path(@fund)
    respond_to do |format|
      if @result.success?
        format.html { redirect_to @back_to, notice: "Investor advisor was successfully created." }
        format.json { render :show, status: :created, location: @investor_advisor }
      else
        @investor_advisor = @result[:investor_advisor]
        @investor_advisor.errors.add(:base, @result[:errors]) if @investor_advisor.errors.blank?

        format.html do
          render :new_for_investor, status: :unprocessable_entity, locals: { advisor_entity_name: params[:investor_advisor][:advisor_entity_name], first_name: params[:investor_advisor][:first_name], last_name: params[:investor_advisor][:last_name], back_to: @back_to, investor_id: @investor.id, fund_id: @fund.id }
        end

        format.json { render json: @investor_advisor.errors, status: :unprocessable_entity }
      end
    end
  end

  # POST /investor_advisors or /investor_advisors.json
  def create
    @investor_advisor = InvestorAdvisor.new(investor_advisor_params)
    @investor_advisor.created_by = current_user
    @investor_advisor.acting_user = current_user
    authorize(@investor_advisor)

    respond_to do |format|
      if @investor_advisor.save
        format.html { redirect_to investor_advisor_url(@investor_advisor), notice: "Investor advisor was successfully created." }
        format.json { render :show, status: :created, location: @investor_advisor }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @investor_advisor.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /investor_advisors/1 or /investor_advisors/1.json
  def update
    @investor_advisor.acting_user = current_user
    respond_to do |format|
      # S1: entity_id / email are NOT editable. `update?` authorized the grant as it was loaded
      # (set_investor_advisor), so accepting a new entity_id here would let an admin of entity A
      # re-point a grant at any other tenant and the advisor would switch in with its roles.
      if @investor_advisor.update(investor_advisor_update_params)
        format.html { redirect_to investor_advisor_url(@investor_advisor), notice: "Investor advisor was successfully updated." }
        format.json { render :show, status: :ok, location: @investor_advisor }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @investor_advisor.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /investor_advisors/1 or /investor_advisors/1.json
  def destroy
    @investor_advisor.destroy

    respond_to do |format|
      format.html { redirect_to investor_advisors_url, notice: "Investor advisor was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def switch
    if params[:id].present?
      @investor_advisor = InvestorAdvisor.find(params[:id])
      authorize(@investor_advisor)
      @investor_advisor.switch(current_user)
      # S8: layouts/_alerts renders flashes html_safe and the entity name is admin-editable.
      notice = "You have now been switched to the advisor role for #{ERB::Util.html_escape(@investor_advisor.entity.name)}."
      # The Access Denied "Switch to ..." button sends the page it was denied on, so the advisor
      # lands back there. Worked examples H8, X10 —
      # openspec/changes/fix-advisor-own-investor-access/report.md#verification
      if (return_to = local_return_path(params[:return_to]))
        redirect_to(return_to, notice:)
      else
        redirect_back_or_to(root_path, notice:)
      end
    else
      # Finding 3: The revert path must check that the user is actually an advisor
      # currently switched into another entity. This prevents account corruption
      # for regular users and unauthorized session disruption.
      raise Pundit::NotAuthorizedError unless current_user.investor_advisor?

      InvestorAdvisor.revert(current_user, params[:persona])
      redirect_back_or_to(root_path, notice: "You have now been switched out of the advisor role.")
    end
  end

  private

  # A same-site path only ("/funds/1?tab=x"): anything with a scheme or host, protocol-relative
  # ("//evil.com") or backslash tricks is dropped, so return_to can never become an open redirect.
  def local_return_path(value)
    path = value.to_s
    return nil unless path.start_with?("/") && !path.start_with?("//") && path.exclude?("\\")

    uri = URI.parse(path)
    uri.scheme.nil? && uri.host.nil? ? path : nil
  rescue URI::InvalidURIError
    nil
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_investor_advisor
    @investor_advisor = InvestorAdvisor.find(params[:id])
    authorize(@investor_advisor)
    @bread_crumbs = { 'Investor Advisors': investor_advisors_path, @investor_advisor.user.email => investor_advisor_path(@investor_advisor) }
  end

  # Only allow a list of trusted parameters through.
  # Note: :user_id is intentionally omitted — it is resolved server-side from :email via ensure_user.
  # Finding 5: permissions and extended_permissions are kept here per user requirement (SEC-14),
  # allowing entity admins to set them from the UI.
  def investor_advisor_params
    params.require(:investor_advisor).permit(:entity_id, :email, allowed_roles: [], permissions: [], extended_permissions: [])
  end

  # The edit form changes only what the advisor may do. Which tenant the grant belongs to and whose
  # login it is are fixed at creation (create authorizes the new entity_id).
  # Worked example S1 — openspec/changes/fix-tenant-isolation-batch1/report.md#verification
  def investor_advisor_update_params
    params.require(:investor_advisor).permit(allowed_roles: [], permissions: [], extended_permissions: [])
  end
end
