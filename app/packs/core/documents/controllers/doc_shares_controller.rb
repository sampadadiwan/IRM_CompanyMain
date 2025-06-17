class DocSharesController < ApplicationController
  before_action :authenticate_user!, except: %i[view]
  before_action :set_doc_share, only: %i[show edit update destroy]
  after_action :verify_authorized, except: %i[index view]
  after_action :verify_policy_scoped, only: %i[index]

  def index
    @doc_shares = policy_scope(DocShare)
  end

  def show; end

  # rubocop:disable Rails/SkipsModelValidations
  def view
    token = params[:token]
    doc_share_id = DocShareTokenService.new.verify_token(token)

    unless doc_share_id
      Rails.logger.warn("DocShare: Invalid or expired token received: #{token}")
      return render_not_found
    end

    @doc_share = DocShare.find_by(id: doc_share_id)

    unless @doc_share
      Rails.logger.warn("DocShare: DocShare record not found for ID: #{doc_share_id}")
      return render_not_found
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      # Increment view count and update viewed_at
      @doc_share.increment!(:view_count)
      @doc_share.update(viewed_at: Time.current) if @doc_share.viewed_at.blank?
    end

    @document = @doc_share.document
    render '/documents/show', locals: { document: @doc_share.document }
  rescue StandardError => e
    Rails.logger.error("DocShare: Unhandled exception in view action: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    render_not_found # Render 404 for any unhandled error during debugging
  end
  # rubocop:enable Rails/SkipsModelValidations

  def render_not_found
    render plain: "Not Found", status: :not_found, layout: false
  end

  def new
    @doc_share = DocShare.new(document_id: params[:document_id])
    authorize @doc_share
  end

  def edit; end

  def create
    emails_input = params[:doc_share][:email].to_s
    emails = emails_input.split(',').map(&:strip).reject(&:empty?)

    common_params = doc_share_base_params
    successful_shares = []
    failed_shares = []

    emails.each do |email|
      doc_share_attributes = common_params.merge(email: email)
      @doc_share = DocShare.new(doc_share_attributes)
      authorize @doc_share

      if DocShareCreationService.wtf?(doc_share: @doc_share).success?
        successful_shares << @doc_share
      else
        failed_shares << @doc_share
      end
    end

    respond_to do |format|
      if failed_shares.empty? && !successful_shares.empty?
        format.html { redirect_to document_url(@doc_share.document_id), notice: "Doc shares were successfully created." }
        format.json { render json: { message: "Doc shares were successfully created.", successful_shares: successful_shares.map(&:id) }, status: :created }
      elsif successful_shares.empty? && !failed_shares.empty?
        # All failed
        @doc_share = failed_shares.first # Use the first failed share for error rendering
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { message: "Failed to create doc shares.", errors: failed_shares.map { |ds| { email: ds.email, errors: ds.errors.full_messages } } }, status: :unprocessable_entity }
      else # Partial success
        format.html { redirect_to document_url(@doc_share.document_id), notice: "Some doc shares were created, but others failed." }
        format.json { render json: { message: "Some doc shares were created, but others failed.", successful_shares: successful_shares.map(&:id), failed_shares: failed_shares.map { |ds| { email: ds.email, errors: ds.errors.full_messages } } }, status: :multi_status }
      end
    end
  end

  def update
    respond_to do |format|
      if @doc_share.update(doc_share_params)
        format.html { redirect_to @doc_share, notice: "Doc share was successfully updated." }
        format.json { render :show, status: :ok, location: @doc_share }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @doc_share.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @doc_share.destroy
    respond_to do |format|
      format.html { redirect_to document_url(@doc_share.document_id), notice: "Doc share was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  def set_doc_share
    @doc_share = DocShare.find(params[:id])
    authorize @doc_share
  end

  def doc_share_params
    # This method is now deprecated for `create` action, use doc_share_base_params instead
    params.require(:doc_share).permit(:email, :email_sent, :viewed_at, :view_count, :document_id)
  end

  def doc_share_base_params
    params.require(:doc_share).permit(:email_sent, :viewed_at, :view_count, :document_id)
  end
end
