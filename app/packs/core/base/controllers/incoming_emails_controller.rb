class IncomingEmailsController < ApplicationController
  before_action :set_incoming_email, only: %i[show edit update destroy]
  skip_before_action :verify_authenticity_token, only: [:sendgrid]
  skip_before_action :set_current_entity, only: [:sendgrid]
  skip_before_action :authenticate_user!, only: [:sendgrid]
  skip_after_action :verify_authorized, only: [:sendgrid]

  def sendgrid
    Rails.logger.debug { "Processing incoming email, to: #{params[:to]}, from: #{params[:from]}, subject: #{params[:subject]}" }

    email = IncomingEmail.new(
      from: params[:from],
      to: params[:to].truncate(255),
      subject: params[:subject],
      body: params[:html].presence || params[:text]
    )

    if email.save
      email.save_attachments(params) if params[:attachments].present?
      head :ok
    else
      Rails.logger.debug email.errors.full_messages
      head :unprocessable_entity
    end
  end

  # GET /incoming_emails
  def index
    @q = IncomingEmail.ransack(params[:q])

    @incoming_emails = policy_scope(@q.result)
    @incoming_emails = @incoming_emails.where(owner_type: params[:owner_type], owner_id: params[:owner_id]) if params[:owner_type].present? && params[:owner_id].present?
    @pagy, @incoming_emails = pagy(@incoming_emails.order(id: :desc))
  end

  # GET /incoming_emails/1
  def show; end

  # GET /incoming_emails/new
  def new
    @incoming_email = IncomingEmail.new
    authorize @incoming_email
  end

  # GET /incoming_emails/1/edit
  def edit; end

  # POST /incoming_emails
  def create
    @incoming_email = IncomingEmail.new(incoming_email_params)
    authorize @incoming_email
    if @incoming_email.save
      redirect_to @incoming_email, notice: "Incoming email was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /incoming_emails/1
  def update
    if @incoming_email.update(incoming_email_params)
      redirect_to @incoming_email, notice: "Incoming email was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /incoming_emails/1
  def destroy
    @incoming_email.destroy!
    redirect_to incoming_emails_url, notice: "Incoming email was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_incoming_email
    @incoming_email = IncomingEmail.find(params[:id])
    authorize @incoming_email
  end

  # Only allow a list of trusted parameters through.
  def incoming_email_params
    params.require(:incoming_email).permit(:from, :to, :subject, :body, :owner_id, :owner_type, :entity_id)
  end
end
