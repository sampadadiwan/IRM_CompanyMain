class ApprovalResponsesController < ApplicationController
  before_action :authenticate_user!, except: %w[email_response]
  before_action :set_approval_response, only: %i[show edit update destroy approve preview]
  after_action :verify_authorized, except: %i[index search email_response]

  # GET /approval_responses or /approval_responses.json
  def index
    @approval_responses = policy_scope(ApprovalResponse).includes(:approval, :entity, :response_user, :investor)
    @approval = nil
    if params[:approval_id].present?
      @approval = Approval.find(params[:approval_id])
      @approval_responses = @approval_responses.where(approval_id: params[:approval_id])
    end
    @approval_responses = @approval_responses.where(status: params[:status]) if params[:status].present?
  end

  # GET /approval_responses/1 or /approval_responses/1.json
  def show; end

  # GET /approval_responses/new
  def new
    @approval_response = ApprovalResponse.new(approval_response_params)
    @approval_response.response_entity_id = current_user.entity_id
    @approval_response.response_user_id = current_user.id
    @approval_response.entity_id = @approval_response.approval.entity_id
    authorize @approval_response
    setup_custom_fields(@approval_response)
  end

  # GET /approval_responses/1/edit
  def edit
    setup_custom_fields(@approval_response)
  end

  # POST /approval_responses or /approval_responses.json
  def create
    @approval_response = ApprovalResponse.new(approval_response_params)
    @approval_response.response_entity_id = @approval_response.investor.investor_entity_id
    @approval_response.entity_id = @approval_response.approval.entity_id
    @approval_response.status = "Pending"

    authorize @approval_response

    respond_to do |format|
      if @approval_response.save
        format.html { redirect_to approval_response_url(@approval_response), notice: "Approval response was successfully created." }
        format.json { render :show, status: :created, location: @approval_response }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @approval_response.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /approval_responses/1 or /approval_responses/1.json
  def update
    respond_to do |format|
      if @approval_response.update(approval_response_params)
        format.html { redirect_to approval_response_url(@approval_response), notice: "Approval response was successfully updated." }
        format.json { render :show, status: :ok, location: @approval_response }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @approval_response.errors, status: :unprocessable_entity }
      end
    end
  end

  def approve
    @approval_response.status = params[:status]
    @approval_response.properties = params[:approval_response][:properties] if params[:approval_response] && params[:approval_response][:properties].present?
    @approval_response.response_user_id = current_user.id
    saved = @approval_response.save
    # H34: a bearer-token caller gets JSON, not a 302; the website keeps its redirect
    if api_request?
      return render(:show, status: :ok) if saved

      return render(json: @approval_response.errors, status: :unprocessable_entity)
    end

    if saved
      redirect_to approval_url(@approval_response.approval), notice: "Successfully #{params[:status]}."
    else
      redirect_to approval_url(@approval_response.approval), alert: "Failed to register response: #{@approval_response.errors.messages.values.flatten}"
    end
  end

  # The investor's emailed answer links (approval_mailer/_response_link). Opening a link (GET) only
  # shows a confirm card; the answer is saved by the POST from that card. Mail scanners (Safe Links,
  # Mimecast, …) open every link in an email, so a GET that saved would register whichever option
  # the scanner happened to fetch last, as the investor.
  def email_response
    # The signed link: bound to this response and the recipient's email, 7 days
    @approval_response = email_link_response
    # Stripped: links sent before this change carry " Rejected" for options typed "Approved, Rejected"
    @status = params[:status].to_s.strip
    approval = @approval_response&.approval

    @msg = if @approval_response.nil?
             "Failed to register response: Invalid link."
           elsif approval.due_date < Time.zone.today
             # Same rule as answering in the app (ApprovalResponsePolicy#approve?)
             "This approval closed on #{l(approval.due_date)}."
           elsif approval.offered_statuses.exclude?(@status) || @status == "Pending"
             "Failed to register response: #{@status} is not a response option for this approval."
           elsif request.post?
             record_email_response
           end
    # @msg nil = GET of a valid link: the view shows the confirm card
  end

  # DELETE /approval_responses/1 or /approval_responses/1.json
  def destroy
    @approval_response.destroy

    respond_to do |format|
      format.html { redirect_to approval_responses_url, notice: "Approval response was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # The response an emailed answer link points at, or nil when the link is missing, tampered with,
  # expired, or signed for another response.
  def email_link_response
    return nil if params[:signed_id].blank? || params[:email].blank?

    response = ApprovalResponse.find_signed(params[:signed_id], purpose: "approval_response-#{params[:email]}")
    response if response&.id == params[:id].to_i
  end

  # Saves the confirmed answer as the link's recipient; returns the message the card shows
  def record_email_response
    user = User.find_by(email: params[:email])
    return "Failed to register response: Invalid link." unless user

    ActiveRecord::Base.connected_to(role: :writing) do
      if @approval_response.update(status: @status, response_user_id: user.id)
        "Successfully registered response: #{@status}."
      else
        "Failed to register response: #{@approval_response.errors.full_messages.join(', ')}"
      end
    end
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_approval_response
    @approval_response = ApprovalResponse.find(params[:id])
    authorize @approval_response
  end

  # Only allow a list of trusted parameters through.
  def approval_response_params
    params.require(:approval_response).permit(:entity_id, :approval_id, :status, :details, :investor_id, :owner_type, :owner_id, properties: {})
  end
end
