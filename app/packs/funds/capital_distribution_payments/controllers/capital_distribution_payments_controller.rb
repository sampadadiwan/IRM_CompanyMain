class CapitalDistributionPaymentsController < ApplicationController
  before_action :set_capital_distribution_payment, only: %i[show edit update destroy preview generate_docs]

  # GET /capital_distribution_payments or /capital_distribution_payments.json
  def index
    @q = CapitalDistributionPayment.ransack(params[:q])

    @capital_distribution_payments = policy_scope(@q.result).includes(:entity, :fund, :capital_distribution, :capital_commitment, :investor_kyc)

    @capital_distribution_payments = @capital_distribution_payments.where(id: search_ids) if params[:search] && params[:search][:value].present?

    @capital_distribution_payments = @capital_distribution_payments.where(fund_id: params[:fund_id]) if params[:fund_id].present?

    @capital_distribution_payments = @capital_distribution_payments.where(capital_distribution_id: params[:capital_distribution_id]) if params[:capital_distribution_id].present?

    @capital_distribution_payments = @capital_distribution_payments.where(capital_commitment_id: params[:capital_commitment_id]) if params[:capital_commitment_id].present?

    @capital_distribution_payments = @capital_distribution_payments.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?

    if params[:all].blank? && !request.format.xlsx?
      per_page = params[:per_page]&.to_i || 10
      @capital_distribution_payments = @capital_distribution_payments.page(params[:page]).per(per_page)
    end

    respond_to do |format|
      format.html
      format.xlsx
      format.json { render json: CapitalDistributionPaymentDatatable.new(params, capital_distribution_payments: @capital_distribution_payments) }
    end
  end

  def search_ids
    # This is only when the datatable sends a search query
    query = "#{params[:search][:value]}*"
    term = { entity_id: current_user.entity_id }

    # Here we search for all the CapitalCommitments that belong to the entity of the current user

    index_search = CapitalDistributionPaymentIndex.filter(term:)
                                                  .query(query_string: { fields: CapitalDistributionPaymentIndex::SEARCH_FIELDS,
                                                                         query:, default_operator: 'and' })

    # Filter by fund, capital_distribution and capital_commitment
    index_search = index_search.filter(term: { fund_id: params[:fund_id] }) if params[:fund_id].present?
    index_search = index_search.filter(term: { capital_distribution_id: params[:capital_distribution_id] }) if params[:capital_distribution_id].present?
    index_search = index_search.filter(term: { capital_commitment_id: params[:capital_commitment_id] }) if params[:capital_commitment_id].present?

    index_search.map(&:id)
  end

  # GET /capital_distribution_payments/1 or /capital_distribution_payments/1.json
  def show; end

  # GET /capital_distribution_payments/new
  def new
    @capital_distribution_payment = CapitalDistributionPayment.new(capital_distribution_payment_params)
    @capital_distribution_payment.entity_id = @capital_distribution_payment.capital_distribution.entity_id
    @capital_distribution_payment.fund_id = @capital_distribution_payment.capital_distribution.fund_id
    @capital_distribution_payment.payment_date = Time.zone.today

    authorize(@capital_distribution_payment)
  end

  # GET /capital_distribution_payments/1/edit
  def edit; end

  # POST /capital_distribution_payments or /capital_distribution_payments.json
  def create
    @capital_distribution_payment = CapitalDistributionPayment.new(capital_distribution_payment_params)
    @capital_distribution_payment.entity_id = @capital_distribution_payment.capital_distribution.entity_id
    @capital_distribution_payment.fund_id = @capital_distribution_payment.capital_distribution.fund_id
    authorize(@capital_distribution_payment)
    result = CapitalDistributionPaymentCreate.call(capital_distribution_payment: @capital_distribution_payment)
    respond_to do |format|
      if result.success?
        format.html { redirect_to capital_distribution_payment_url(@capital_distribution_payment), notice: "Capital distribution payment was successfully created." }
        format.json { render :show, status: :created, location: @capital_distribution_payment }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @capital_distribution_payment.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /capital_distribution_payments/1 or /capital_distribution_payments/1.json
  def update
    @capital_distribution_payment.assign_attributes(capital_distribution_payment_params)
    result = CapitalDistributionPaymentUpdate.call(capital_distribution_payment: @capital_distribution_payment)
    respond_to do |format|
      if result.success?
        format.html { redirect_to capital_distribution_payment_url(@capital_distribution_payment), notice: "Capital distribution payment was successfully updated." }
        format.json { render :show, status: :ok, location: @capital_distribution_payment }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @capital_distribution_payment.errors, status: :unprocessable_entity }
      end
    end
  end

  # Generated Distribution Notice For all thhe payment
  def generate_docs
    CapitalDistributionPaymentDocJob.perform_later(@capital_distribution_payment.capital_distribution_id, @capital_distribution_payment.id, current_user.id)
    redirect_to capital_distribution_payment_path(@capital_distribution_payment), notice: "Documentation generation started, please check back in a few mins."
  end

  # DELETE /capital_distribution_payments/1 or /capital_distribution_payments/1.json
  def destroy
    @capital_distribution_payment.destroy

    respond_to do |format|
      format.html { redirect_to capital_distribution_payments_url, notice: "Capital distribution payment was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_capital_distribution_payment
    @capital_distribution_payment = CapitalDistributionPayment.find(params[:id])
    authorize(@capital_distribution_payment)
    @bread_crumbs = { Funds: funds_path,
                      "#{@capital_distribution_payment.fund.name}": fund_path(@capital_distribution_payment.fund),
                      "#{@capital_distribution_payment.capital_distribution}": capital_distribution_path(id: @capital_distribution_payment.capital_distribution_id),
                      "#{@capital_distribution_payment}": nil }
  end

  # Only allow a list of trusted parameters through.
  def capital_distribution_payment_params
    params.require(:capital_distribution_payment).permit(:fund_id, :entity_id, :capital_distribution_id, :investor_id, :form_type_id, :income, :payment_date, :completed, :folio_id, properties: {})
  end
end
