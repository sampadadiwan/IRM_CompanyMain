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

  def paginate
    folio_filter = @q.conditions.any? do |cond|
      cond.attributes.any? { |attr| attr.name == 'folio_id' }
    end

    capital_commitment_filter = @q.conditions.any? do |cond|
      cond.attributes.any? { |attr| attr.name == 'capital_commitment_id' }
    end

    per_page = params[:per_page] || 10
    per_page = 10_000 if per_page.to_i > 10_000
    # if no ordering (in  sql query) or by ransack then we order by reporting_date asc by default
    @account_entries = @account_entries.order(reporting_date: :asc, created_at: :asc) if @account_entries.arel.orders.blank? && !ransack_has_attr?(params[:q], 's')
    if capital_commitment_filter || folio_filter
      @pagy, @account_entries = pagy(@account_entries, limit: per_page) if params[:all].blank?
    elsif params[:all].blank?
      @pagy, @account_entries = pagy_countless(@account_entries, limit: per_page)
    end
  end

  # GET /account_entries or /account_entries.json
  def index
    authorize AccountEntry

    result = AccountEntryList.call(current_user, params, request.referer) { |relation| policy_scope(relation) }

    if result.error
      redirect_to result.redirect_url, alert: result.error
      return
    end

    @q = result.q
    @fund = result.fund
    @account_entries = result.account_entries
    @data_frame = result.data_frame
    @adhoc_json = result.adhoc_json
    @template = result.template
    @time_series = result.time_series
    @pivot = result.pivot

    paginate if @template == "index" && params[:group_fields].blank? && params[:time_series].blank? && params[:pivot] != "true"

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
    # Find the account entry by ID, but the table is partitioned by reporting_date, so if we have that use it to reduce partition queries
    @account_entry = if params[:reporting_date].present?
                       AccountEntry.find_by(id: params[:id], reporting_date: params[:reporting_date])
                     else
                       AccountEntry.find(params[:id])
                     end

    authorize @account_entry
    @bread_crumbs = { Funds: funds_path,
                      "#{@account_entry.fund.name}": fund_path(@account_entry.fund) }
    @bread_crumbs[@account_entry.capital_commitment.to_s] = capital_commitment_path(@account_entry.capital_commitment, tab: "account-entries-tab") if @account_entry.capital_commitment

    @bread_crumbs[@account_entry.to_s] = nil
  end

  # Only allow a list of trusted parameters through.
  def account_entry_params
    params.require(:account_entry).permit(:capital_commitment_id, :entity_id, :fund_id, :investor_id, :folio_id, :reporting_date, :entry_type, :name, :amount, :notes, :period, :form_type_id, :parent_type, :parent_id, properties: {})
  end
end
