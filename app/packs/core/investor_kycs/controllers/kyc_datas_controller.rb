class KycDatasController < ApplicationController
  before_action :set_kyc_data, only: %i[show edit update toggle_approved refresh send_ckyc_otp download_ckyc_with_otp destroy]
  after_action :verify_authorized, except: %i[index search show]

  def index
    @kyc_datas = policy_scope(KycData).includes(:investor_kyc)
    authorize(KycData)
    @kyc_datas = @kyc_datas.where(investor_kyc_id: params[:investor_kyc_id]) if params[:investor_kyc_id].present?
    @kyc_datas = @kyc_datas.where(source: params[:source]) if params[:source].present?
    @pagy, @kyc_datas = pagy(@kyc_datas) if params[:all].blank?
    respond_to do |format|
      format.html
      format.turbo_stream
      format.json
    end
  end

  def search
    if params[:query].present?
      entity_ids = [current_user.entity_id]

      @kyc_datas = KycData.filter(terms: { entity_id: entity_ids })
                          .query(query_string: {
                                   fields: KycDataIndex::SEARCH_FIELDS,
                                   query: params[:query],
                                   default_operator: 'and'
                                 })
      @pagy, @kyc_datas = pagy(@kyc_datas.page(params[:page]).objects)

      render :index
    else
      redirect_to kyc_datas_path(request.parameters)
    end
  end

  def show
    authorize(@kyc_data)
    respond_to do |format|
      format.html
      format.json { render json: @kyc_data }
    end
  end

  # Renders the form for creating a new KYCData record
  def new
    @kyc_data = KycData.new(kyc_data_params)

    # If the entity is not explicitly set, inherit it from the linked investor_kyc
    @kyc_data.entity ||= @kyc_data.investor_kyc.entity

    # Authorization check
    authorize(@kyc_data)

    # Set up breadcrumbs for UI navigation
    bread_crumb_text = if @kyc_data.kra?
                         "New KRA Data"
                       elsif @kyc_data.ckyc?
                         "New CKYC Data"
                       else
                         "New KYC Data"
                       end

    @bread_crumbs = {
      KYCs: investor_kycs_path,
      "#{@kyc_data.investor_kyc.full_name}": investor_kyc_path(@kyc_data.investor_kyc),
      "#{bread_crumb_text}": new_kyc_data_path
    }
  end

  # Handles submission of the new KYCData form
  def create
    @kyc_data = KycData.new(kyc_data_params)
    authorize(@kyc_data)

    if @kyc_data.save
      if @kyc_data.kra?
        # If KRA, immediately fetch the KRA data
        kra_success, msg = CkycKraService.new.get_kra_data(@kyc_data)
        if kra_success
          redirect_to kyc_data_path(@kyc_data), notice: "KRA Data fetched successfully."
        else
          redirect_to kyc_data_path(@kyc_data), alert: "Failed to fetch KRA Data. #{msg}"
        end
      else
        # If CKYC, start OTP process
        UserAlert.new(message: "Sending OTP", user_id: current_user.id, level: :info).broadcast
        redirect_to send_ckyc_otp_kyc_data_path(id: @kyc_data.id, back_to: kyc_data_path(@kyc_data))
      end
    else
      # Show form again with validation errors
      render :new, status: :unprocessable_entity
    end
  end

  # Renders edit form for KYCData, allowing correction of PAN, DOB, etc.
  def edit
    authorize(@kyc_data)
    respond_to do |format|
      format.html
    end
  end

  # Handles updating an existing KYCData record
  def update
    authorize(@kyc_data)

    if @kyc_data.update(kyc_data_params)
      if @kyc_data.kra?
        kra_success, msg = CkycKraService.new.get_kra_data(@kyc_data)
        if kra_success
          redirect_to kyc_data_url(@kyc_data), notice: "KRA Data was successfully fetched."
        else
          @kyc_data.errors.add(:base, msg)
          redirect_to kyc_data_url(@kyc_data), alert: "Failed to Fetch KRA Data"
        end
      elsif @kyc_data.ckyc?
        # If CKYC, re-trigger OTP flow (performs search if CKYC Number is not set)
        UserAlert.new(message: "Sending OTP", user_id: current_user.id, level: :info).broadcast
        redirect_to send_ckyc_otp_kyc_data_path(id: @kyc_data.id, back_to: kyc_data_path(@kyc_data))
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Compares CKYC and KRA data side-by-side for an InvestorKYC
  # Falls back to fetch if either is missing
  def compare_ckyc_kra # rubocop:disable Metrics/MethodLength
    @ckyc_data = nil
    @kra_data = nil
    authorize(KycData)

    if params[:investor_kyc_id].present?
      @investor_kyc = InvestorKyc.find(params[:investor_kyc_id])
      @ckyc_data = @investor_kyc.ckyc_data
      @kra_data = @investor_kyc.kra_data

      if @ckyc_data.blank? && @kra_data.blank?
        msg = "No CKYC/KRA Data found"
        msg = "Skipped CKYC/KRA as PAN is not provided." if @investor_kyc.PAN.blank?
        redirect_to edit_investor_kyc_path(@investor_kyc), alert: msg
      else
        # Prepare breadcrumb navigation
        bread_crumb_text = if @ckyc_data.present? && @kra_data.present?
                             "CKYC - KRA Data"
                           elsif @ckyc_data.present?
                             "CKYC Data"
                           elsif @kra_data.present?
                             "KRA Data"
                           else
                             "KYC Data"
                           end

        @bread_crumbs = {
          KYCs: investor_kycs_path,
          "#{@investor_kyc.full_name}": investor_kyc_path(@investor_kyc),
          "#{bread_crumb_text}": kyc_datas_path(investor_kyc_id: @investor_kyc.id)
        }

        respond_to do |format|
          format.html do
            render :compare_ckyc_kra,
                   locals: {
                     investor_kyc: @investor_kyc,
                     ckyc_data: @ckyc_data,
                     kra_data: @kra_data
                   }
          end
        end
      end
    else
      redirect_to investor_kycs_path, status: :unprocessable_entity, alert: "Investor KYC ID is required."
    end
  end

  # Sends OTP to retrieve CKYC data, either by searching or directly using identifier
  def send_ckyc_otp
    success, msg, request_id = ActiveRecord::Base.connected_to(role: :writing) do
      if @kyc_data.external_identifier.blank?
        # If CKYC Number is not present, search by PAN and send OTP
        CkycKraService.new.search_ckyc_data_and_send_otp(@kyc_data)
      else
        # If CKYC Number already known, directly send OTP
        CkycKraService.new.send_ckyc_otp(@kyc_data)
      end
    end

    back_to = params[:back_to] || compare_ckyc_kra_kyc_datas_path(investor_kyc_id: @kyc_data.investor_kyc_id)

    if success
      # Show OTP entry page
      flash.now[:notice] = msg
      render :enter_ckyc_otp, locals: { ckyc_data: @kyc_data, request_id: request_id, back_to: back_to }
    else
      # Log and redirect on failure
      UserAlert.new(message: msg, user_id: current_user.id, level: :danger).broadcast
      redirect_to back_to, alert: msg
    end
  end

  # After user enters OTP, this action is triggered to download CKYC data
  def download_ckyc_with_otp
    otp, request_id = params.values_at(:otp, :request_id)
    back_to = params[:back_to] || compare_ckyc_kra_kyc_datas_path(investor_kyc_id: @kyc_data.investor_kyc_id)

    # Check for presence of both required fields
    if otp.blank? || request_id.blank?
      missing = []
      missing << "Request ID" if request_id.blank?
      missing << "OTP" if otp.blank?
      redirect_to back_to, alert: "#{missing.join(' and ')} required."
      return
    end

    # Fetch CKYC data using OTP and request ID
    success, msg = CkycKraService.new.get_ckyc_data(otp, @kyc_data, request_id)
    flash[success ? :notice : :alert] = msg
    redirect_to back_to
  end

  # Used to re-fetch CKYC or KRA data again based on existing KycData record
  def refresh
    msg = ""
    back_to = params[:back_to] || kyc_data_path(@kyc_data)

    if @kyc_data.kra?
      kra_success, msg = CkycKraService.new.get_kra_data(@kyc_data)

      UserAlert.new(
        message: msg,
        user_id: current_user.id,
        level: kra_success ? :success : :danger
      ).broadcast

      flash[kra_success ? :notice : :alert] = msg
      redirect_to back_to
    elsif @kyc_data.ckyc?
      # Re-trigger CKYC OTP flow
      redirect_to send_ckyc_otp_kyc_data_path(id: @kyc_data.id, back_to: back_to)
    end
  end

  def destroy
    @kyc_data.destroy
    redirect_path = params[:investor_kyc_id].present? ? investor_kyc_path(id: @kyc_data.investor_kyc_id) : kyc_datas_path
    respond_to do |format|
      format.html { redirect_to redirect_path, notice: "Kyc Data was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  def set_kyc_data
    @kyc_data = KycData.find(params[:id])
    authorize(@kyc_data)
    @bread_crumbs = { KYCs: investor_kycs_path, "#{@kyc_data.investor_kyc.full_name}": investor_kyc_path(@kyc_data.investor_kyc), "#{@kyc_data.source.upcase} Data": kyc_data_path(@kyc_data) }
  end

  def kyc_data_params
    params.require(:kyc_data).permit(:investor_kyc_id, :entity_id, :source, :PAN, :birth_date, :phone)
  end
end
