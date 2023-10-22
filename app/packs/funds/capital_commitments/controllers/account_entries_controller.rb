class AccountEntriesController < ApplicationController
  include FundsHelper

  before_action :set_account_entry, only: %i[show edit update destroy]
  has_scope :entry_type
  has_scope :folio_id
  has_scope :unit_type
  has_scope :reporting_date_start
  has_scope :reporting_date_end
  has_scope :cumulative, type: :boolean

  # GET /account_entries or /account_entries.json
  def index
    @account_entries = apply_scopes(policy_scope(AccountEntry)).includes(:capital_commitment, :fund)
    @account_entries = @account_entries.where(capital_commitment_id: params[:capital_commitment_id]) if params[:capital_commitment_id]
    @account_entries = @account_entries.where(investor_id: params[:investor_id]) if params[:investor_id]
    @account_entries = @account_entries.where(fund_id: params[:fund_id]) if params[:fund_id]
    @account_entries = @account_entries.where(capital_commitment_id: nil) if params[:fund_accounts_only].present?

    # @account_entries = @account_entries.where(entry_type: params[:entry_type]) if params[:entry_type]
    # @account_entries = @account_entries.where(cumulative: params[:cumulative] == "true") if params[:cumulative]

    @account_entries = @account_entries.page(params[:page]) if params[:all].blank?

    fund_bread_crumbs("Account Entries")

    respond_to do |format|
      format.html
      format.xlsx
      format.json { render json: AccountEntryDatatable.new(params, account_entries: @account_entries) }
    end
  end

  # GET /account_entries/1 or /account_entries/1.json
  def show; end

  # GET /account_entries/new
  def new
    @account_entry = AccountEntry.new(account_entry_params)
    @account_entry.entity_id = @account_entry.fund.entity_id
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
    params.require(:account_entry).permit(:capital_commitment_id, :entity_id, :fund_id, :investor_id, :folio_id, :reporting_date, :entry_type, :name, :amount, :notes, :period, :form_type_id, :commitment_type)
  end
end
