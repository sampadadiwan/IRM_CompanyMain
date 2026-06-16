class PortfolioReportTemplatesController < ApplicationController
  before_action :set_template, only: %i[show edit update destroy]
  before_action :set_portfolio_report

  # GET /portfolio_reports/:portfolio_report_id/portfolio_report_templates
  def index
    authorize PortfolioReportTemplate
    @templates = @portfolio_report.portfolio_report_templates
  end

  # GET /portfolio_report_templates/:id
  def show
    authorize @template
  end

  # GET /portfolio_report_templates/new
  def new
    @template = @portfolio_report.portfolio_report_templates.build
    authorize @template
  end

  # GET /portfolio_report_templates/:id/edit
  def edit
    authorize @template
  end

  # POST /portfolio_reports/:portfolio_report_id/portfolio_report_templates
  def create
    @template = @portfolio_report.portfolio_report_templates.build(template_params)
    authorize @template
    if @template.save
      redirect_to portfolio_report_path(@portfolio_report), notice: "Template created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH /portfolio_report_templates/:id
  def update
    authorize @template
    if @template.update(template_params)
      redirect_to portfolio_report_path(@portfolio_report), notice: "Template updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /portfolio_report_templates/:id
  def destroy
    authorize @template
    @template.destroy
    redirect_to portfolio_report_path(@portfolio_report), notice: "Template deleted."
  end

  private

  def set_portfolio_report
    # shallow routes (edit/show/update/destroy) omit portfolio_report_id —
    # derive it from the template instead
    if params[:portfolio_report_id].present?
      @portfolio_report = PortfolioReport.find(params[:portfolio_report_id])
    elsif @template.present?
      @portfolio_report = @template.portfolio_report
    end
  end

  def set_template
    @template = PortfolioReportTemplate.find(params[:id])
  end

  def template_params
    permitted = params.require(:portfolio_report_template).permit(
      :name, :output_format, :style_document_id,
      :auto_generate_enabled, :auto_generate_frequency, :auto_generate_day,
      branding: %i[primary_color font],
      section_order: [],
      kpi_layout: [:n_periods, :side_by_side, { categories: [], tags: [] }]
    )

    # categories arrives as a comma-separated string from the text input — split it
    if permitted[:kpi_layout] && permitted[:kpi_layout][:categories].is_a?(String)
      permitted[:kpi_layout][:categories] = permitted[:kpi_layout][:categories]
                                            .split(",").map(&:strip).compact_blank
    end

    permitted
  end
end
