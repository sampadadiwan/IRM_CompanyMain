class PortfolioReportDraftsController < ApplicationController
  before_action :set_draft, only: %i[show approve approve_and_export reopen export preview update_kpi_cell update_section regenerate_section]

  # GET /portfolio_report_drafts/:id — step 2: review draft
  def show
    authorize @draft
    @sections     = @draft.portfolio_report.portfolio_report_sections.order(:id)
    @kpi_mappings = @draft.portfolio_company.investor_kpi_mappings
                          .where(id: Array(@draft.selected_kpi_mapping_ids).map(&:to_i))
                          .order(:position)
                          .group_by(&:category)
    # Period labels are the column headers of the KPI table, derived from kpi_table_data keys
    @period_labels = @draft.effective_kpi_table.values.first&.keys || []
  end

  # PATCH /portfolio_report_drafts/:id/approve
  def approve
    authorize @draft
    @draft.update!(status: :approved)
    redirect_to portfolio_report_draft_path(@draft), notice: "Draft approved — ready to export."
  end

  # GET /portfolio_report_drafts/:id/preview — styled HTML mock of Word doc
  def preview
    authorize @draft
    @sections      = @draft.portfolio_report.portfolio_report_sections.order(:id)
    @section_list  = @draft.portfolio_report_template.ordered_section_ids
                           .filter_map { |sid| @sections.find { |s| s.id == sid } }
    @kpi_mappings  = @draft.portfolio_company.investor_kpi_mappings
                           .where(id: Array(@draft.selected_kpi_mapping_ids).map(&:to_i))
                           .order(:position).group_by(&:category)
    @period_labels = @draft.effective_kpi_table.values.first&.keys || []
    render layout: false
  end

  # PATCH /portfolio_report_drafts/:id/approve_and_export — approve then immediately queue export
  def approve_and_export
    authorize @draft
    @draft.update!(status: :exporting)
    PortfolioReportExportJob.perform_later(@draft.id, current_user.id)
    redirect_to portfolio_report_draft_path(@draft), notice: "Approved — export started."
  end

  # PATCH /portfolio_report_drafts/:id/reopen — move approved/exported back to review
  def reopen
    authorize @draft
    @draft.update!(status: :review)
    redirect_to portfolio_report_draft_path(@draft), notice: "Draft reopened for editing."
  end

  # POST /portfolio_report_drafts/:id/export — step 3: render & save document
  def export
    authorize @draft
    @draft.update!(status: :exporting)
    PortfolioReportExportJob.perform_later(@draft.id, current_user.id)
    redirect_to portfolio_report_draft_path(@draft), notice: "Export started."
  end

  # PATCH /portfolio_report_drafts/:id/update_kpi_cell
  # params: { metric_id:, period_label:, value: }
  def update_kpi_cell
    authorize @draft
    @draft.override_kpi_cell(params[:metric_id], params[:period_label], params[:value])
    @draft.save!
    render json: { ok: true }
  end

  # PATCH /portfolio_report_drafts/:id/update_section
  # params: { section_id:, text: }
  def update_section
    authorize @draft
    @draft.set_user_edit(params[:section_id], params[:text])
    @draft.save!
    render json: { ok: true }
  end

  # POST /portfolio_report_drafts/:id/regenerate_section
  # params: { section_id: }
  def regenerate_section
    authorize @draft
    section_id = params[:section_id].to_i
    PortfolioReportSectionRegenerateJob.perform_later(@draft.id, section_id, current_user.id)
    redirect_to portfolio_report_draft_path(@draft),
                notice: "Regenerating section — you'll be notified when it's ready."
  end

  private

  def set_draft
    @draft = PortfolioReportDraft.find(params[:id])
  end
end
