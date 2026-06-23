class AccountEntryReportsController < ApplicationController
  include FundsHelper

  after_action :verify_authorized

  # GET /account_entry_reports/fund_report
  def fund_report
    # The commitment dropdown is multi-select: 0 selected stays fund-level (optionally
    # narrowed to several folios below), exactly 1 means the user wants that investor's
    # own folio-level report, so hand off to that action.
    if commitment_ids_param.size == 1
      skip_authorization
      redirect_to folio_report_account_entry_reports_path(capital_commitment_id: commitment_ids_param,
                                                            start_date: params[:start_date], end_date: params[:end_date],
                                                            entry_names: entry_names_param) and return
    end

    @fund = policy_scope(Fund).find(params[:fund_id])
    authorize @fund, :period_report?

    page = build_page(fund: @fund)
    assign_page(page)
    @detail_pivot = page.detail_pivot(page: params[:page])

    fund_bread_crumbs("Account Entries Report")
  end

  # GET /account_entry_reports/folio_report
  def folio_report
    # The commitment dropdown is multi-select: 0 selected means the user wants the
    # fund-level report, 2+ means they want a fund-level report filtered to those
    # folios - either way, hand off to the fund_report action instead.
    if commitment_ids_param.size != 1
      skip_authorization
      redirect_to fund_report_account_entry_reports_path(fund_id: params[:fund_id], capital_commitment_id: commitment_ids_param,
                                                           start_date: params[:start_date], end_date: params[:end_date],
                                                           entry_names: entry_names_param) and return
    end

    @capital_commitment = policy_scope(CapitalCommitment).find(commitment_ids_param.first)
    authorize @capital_commitment, :period_report?
    @fund = @capital_commitment.fund

    page = build_page(fund: @fund, capital_commitment: @capital_commitment)
    assign_page(page)
    @entries = page.entries

    @bread_crumbs = { Funds: funds_path,
                      "#{@fund.name}": fund_path(@fund),
                      "#{@capital_commitment}": capital_commitment_path(@capital_commitment) }
    @bread_crumbs["Account Entries Report"] = nil
  end

  # POST /account_entry_reports/generate_commentary
  def generate_commentary
    @fund = policy_scope(Fund).find(params[:fund_id])
    @capital_commitment = policy_scope(CapitalCommitment).find(params[:capital_commitment_id]) if params[:capital_commitment_id].present?

    authorize(@capital_commitment || @fund, :period_report?)

    section_key = params[:section_key]
    start_date = params[:start_date]
    end_date = params[:end_date]
    redirect_path = @capital_commitment ? folio_report_account_entry_reports_path(capital_commitment_id: @capital_commitment.id, start_date: start_date, end_date: end_date) : fund_report_account_entry_reports_path(fund_id: @fund.id, start_date: start_date, end_date: end_date)

    # insight.save! below would otherwise raise ActiveRecord::RecordInvalid/StatementInvalid
    # (uncaught, 500) for a tampered or missing param instead of a clean redirect.
    valid_section = AccountEntryReportInsight::SECTION_KEYS.include?(section_key)
    redirect_to redirect_path, alert: "Invalid section or date range." and return unless valid_section && start_date.present? && end_date.present?

    mark_pending_and_enqueue(section_key, start_date, end_date)

    redirect_to redirect_path, notice: "AI commentary is being generated. Refresh in a moment to see it."
  end

  private

  def build_page(fund:, capital_commitment: nil)
    AccountEntryReportPage.new(
      fund: fund, capital_commitment: capital_commitment,
      start_date_param: params[:start_date], end_date_param: params[:end_date],
      entry_names: entry_names_param, commitment_ids: commitment_ids_param
    )
  end

  def assign_page(page)
    @start_date = page.start_date
    @end_date = page.end_date
    @entry_names = page.entry_names
    @commitment_ids = page.commitment_ids
    @available_entry_names = page.available_entry_names
    @report = page.report
    @insights = page.insights
  end

  def entry_names_param
    Array(params[:entry_names]).reject(&:blank?)
  end

  def commitment_ids_param
    Array(params[:capital_commitment_id]).reject(&:blank?)
  end

  def mark_pending_and_enqueue(section_key, start_date, end_date)
    insight = ActiveRecord::Base.connected_to(role: :writing) do
      insight = AccountEntryReportInsight.find_or_initialize_by(
        fund_id: @fund.id, capital_commitment_id: @capital_commitment&.id,
        start_date: start_date, end_date: end_date, section_key: section_key
      )
      insight.entity_id ||= @fund.entity_id
      insight.status = "pending"
      insight.save!
      insight
    end

    AccountEntryReportCommentaryJob.perform_later(
      @fund.id, section_key, start_date.to_s, end_date.to_s,
      capital_commitment_id: @capital_commitment&.id, user_id: current_user.id
    )

    insight
  end
end
