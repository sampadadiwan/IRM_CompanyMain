class AccountEntriesController < ApplicationController
  include FundsHelper

  after_action :verify_authorized, except: %i[index delete_all]
  before_action :set_account_entry, only: %i[show edit update destroy]

  def adhoc
    authorize AccountEntry
    if params[:query].present? || params[:group_fields].present?
      @account_entries = policy_scope(AccountEntry)
      df = AccountEntryDf.df(@account_entries, current_user, params)
      if params[:group_fields].present?
        @adhoc_json = df.to_a.to_json
      elsif params[:query].present?
        @adhoc_json = AiPolars.run_query(params[:query], [AccountEntry, CapitalCommitment, Fund], df)
      end
    end
  end

  def filter_index(params)
    # Step 1: Apply basic equality filters using shared helper
    @account_entries = filter_params(
      @account_entries,
      :capital_commitment_id,
      :investor_id,
      :import_upload_id,
      :fund_id,
      :entry_type,
      :folio_id,
      :unit_type,
      :cumulative,
      :parent_id,
      :parent_type
    )

    # Step 2: Special case - only fund-level accounts (no capital commitment)
    @account_entries = @account_entries.where(capital_commitment_id: nil) if params[:fund_accounts_only].present?

    # Step 3: Apply reporting_date range filter (start and/or end)
    @account_entries = filter_range(
      @account_entries,
      :reporting_date,
      start_date: params[:reporting_date_start],
      end_date: params[:reporting_date_end]
    )
  end

  def check_time_series_params
    @time_series_error = []

    if params[:fund_id].blank?
      params[:fund_id] = current_user.entity.funds.first&.id
      @time_series_error << "Please select a fund."
    end
    # Ensure that folio_id is not nil in the ransack params
    unless @q.conditions.any? { |c| c.attributes.map(&:name).include?('folio_id') }
      # Add a condition to the ransack query where folio_id is XYX
      params[:q] ||= {}
      params[:q][:folio_id_eq] = "Please Enter Folio ID"
      # Redirect to the current path with notice
      @time_series_error << "Please select a folio."
    end

    unless @q.conditions.any? { |c| c.attributes.map(&:name).include?('reporting_date') }
      # Add a condition to the ransack query where folio_id is XYX
      params[:q] ||= {}
      params[:q][:reporting_date] = Time.zone.today
      # Redirect to the current path with notice
      @time_series_error << "Please select a reporting date."
    end

    @time_series_error.join(" ") if @time_series_error.present?
  end

  def fetch_rows
    @q = AccountEntry.ransack(params[:q])
    @account_entries = policy_scope(@q.result).includes(:capital_commitment, :fund)
    filter_index(params)
    @fund = Fund.find(params[:fund_id]) if params[:fund_id].present?

    if params[:group_fields].present?
      # Create a data frame to group the data
      @data_frame = AccountEntryDf.new.df(@account_entries, current_user, params)
      @adhoc_json = @data_frame.to_a.to_json
      @template = params[:template].presence || "index"
    elsif params[:time_series].present?
      # Create a time series view
      error = check_time_series_params
      if error
        # Redirect to the referrer with an error message
        redirect_url = request.referer || account_entries_path(params: params.to_unsafe_h)
        redirect_to redirect_url, alert: error
        return
      end
      @time_series = AccountEntryTimeSeries.new(@account_entries).call
    elsif params[:pivot] == "true"
      # Create a pivot table
      group_by_param = params[:group_by] || 'entry_type' # can be "name" or "entry_type"
      show_breakdown = params[:show_breakdown] == "true" # can be "true" or "false"
      @pivot = AccountEntryPivot.new(@account_entries.includes(:fund), group_by: group_by_param, show_breakdown:).call
    else
      # Default rows view
      @account_entries = AccountEntrySearch.perform(@account_entries, current_user, params)

      paginate
      @template = "index"
    end
  end

  def paginate
    folio_filter = @q.conditions.any? do |cond|
      cond.attributes.any? { |attr| attr.name == 'folio_id' }
    end

    capital_commitment_filter = @q.conditions.any? do |cond|
      cond.attributes.any? { |attr| attr.name == 'capital_commitment_id' }
    end

    if capital_commitment_filter || folio_filter
      @pagy, @account_entries = pagy(@account_entries, limit: params[:per_page] || 10) if params[:all].blank?
    elsif params[:all].blank?
      @pagy, @account_entries = pagy_countless(@account_entries, limit: params[:per_page] || 10)
    end
  end

  # GET /account_entries or /account_entries.json
  def index
    authorize AccountEntry

    fetch_rows

    # Set the breadcrumbs
    fund_bread_crumbs("Account Entries")

    respond_to do |format|
      format.html do
        render @template
      end
      format.xlsx do
        template = params[:template].presence || "index"
        render xlsx: template, filename: "account_entries.xlsx"
      end
      format.json
    end
  end

  # GET /account_entries/1 or /account_entries/1.json
  def show; end

  # GET /account_entries/new
  def new
    @account_entry = AccountEntry.new(account_entry_params)
    @account_entry.entity_id = current_user.entity_id
    authorize @account_entry
    @account_entry.investor_id = @account_entry.capital_commitment&.investor_id
    @account_entry.folio_id = @account_entry.capital_commitment&.folio_id
    @account_entry.reporting_date = Time.zone.today
    setup_custom_fields(@account_entry)
  end

  # GET /account_entries/1/edit
  def edit
    setup_custom_fields(@account_entry)
  end

  # POST /account_entries or /account_entries.json
  def create
    @account_entry = AccountEntry.new(account_entry_params)
    authorize @account_entry

    respond_to do |format|
      if @account_entry.save
        format.html { redirect_to account_entry_url(@account_entry), notice: "Account entry was successfully created." }
        format.json { render :show, status: :created, location: @account_entry }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @account_entry.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account_entries/1 or /account_entries/1.json
  def update
    respond_to do |format|
      if @account_entry.update(account_entry_params)
        format.html { redirect_to account_entry_url(@account_entry), notice: "Account entry was successfully updated." }
        format.json { render :show, status: :ok, location: @account_entry }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @account_entry.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account_entries/1 or /account_entries/1.json
  def destroy
    @account_entry.destroy

    respond_to do |format|
      format.html { redirect_to account_entries_url, notice: "Account entry was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  def delete_all
    AccountEntryDeleteJob.perform_later(params.to_unsafe_h, current_user.id)
    redirect_to account_entries_path(params: params.to_unsafe_h), notice: "Account entries deletion in progress."
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_account_entry
    @account_entry = AccountEntry.find(params[:id])
    authorize @account_entry
    @bread_crumbs = { Funds: funds_path,
                      "#{@account_entry.fund.name}": fund_path(@account_entry.fund) }
    @bread_crumbs[@account_entry.capital_commitment.to_s] = capital_commitment_path(@account_entry.capital_commitment, tab: "account-entries-tab") if @account_entry.capital_commitment

    @bread_crumbs[@account_entry.to_s] = nil
  end

  # Only allow a list of trusted parameters through.
  def account_entry_params
    params.require(:account_entry).permit(:capital_commitment_id, :entity_id, :fund_id, :investor_id, :folio_id, :reporting_date, :entry_type, :name, :amount, :notes, :period, :form_type_id, properties: {})
  end
end
