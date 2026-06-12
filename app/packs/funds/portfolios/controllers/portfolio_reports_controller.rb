class PortfolioReportsController < ApplicationController
  before_action :set_portfolio_report, only: %i[show edit update destroy clone suggest_sections]

  # GET /portfolio_reports
  def index
    @q = PortfolioReport.ransack(params[:q])
    @portfolio_reports = policy_scope(@q.result)
  end

  # GET /portfolio_reports/1
  def show; end

  # GET /portfolio_reports/new
  def new
    @portfolio_report = PortfolioReport.new
    @portfolio_report.entity_id = current_user.entity_id
    @portfolio_report.portfolio_report_sections.build
    authorize @portfolio_report
  end

  # GET /portfolio_reports/1/edit
  def edit; end

  # POST /portfolio_reports
  def create
    @portfolio_report = PortfolioReport.new(portfolio_report_params)
    authorize @portfolio_report
    if @portfolio_report.save
      redirect_to @portfolio_report, notice: "Portfolio report was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /portfolio_reports/1
  def update
    if @portfolio_report.update(portfolio_report_params)
      redirect_to @portfolio_report, notice: "Portfolio report was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # POST /portfolio_reports/:id/suggest_sections — calls LLM to suggest section names + instructions
  # Returns JSON: { sections: [{ name:, instructions:, icon: }, ...] }
  def suggest_sections
    authorize @portfolio_report
    entity = @portfolio_report.entity
    llm    = LlmService.ruby_llm_chat(entity: entity)

    prompt = <<~PROMPT
      You are a private equity analyst helping design the sections for a portfolio company report template.
      Report name: "#{@portfolio_report.name}"

      Suggest 4-6 sections that would make this a comprehensive portfolio monitoring report.
      For each section provide:
        - name: short section title (e.g. "Financial Performance", "Operational Highlights")
        - instructions: 1-2 sentence instructions to an LLM analyst explaining what to write in this section
        - icon: a single Tabler icon name (without the "ti-" prefix) that fits the section theme

      Respond ONLY with a valid JSON array, no markdown, no explanation.
      Example: [{"name":"Financial Performance","instructions":"Summarise revenue and margins...","icon":"chart-bar"}]
    PROMPT

    response = llm.ask(prompt)
    raw      = if response.is_a?(String)
                 response
               else
                 (response.respond_to?(:content) ? response.content : response.to_s)
               end
    cleaned  = raw.gsub(/\A```json\s*|\s*```\z/, "").strip

    sections = JSON.parse(cleaned)
    render json: { sections: sections }
  rescue JSON::ParserError => e
    render json: { error: "Could not parse LLM response: #{e.message}", raw: raw }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # GET  /portfolio_reports/bulk_generate  — form: pick portcos + template
  # POST /portfolio_reports/bulk_generate  — queue draft jobs
  def bulk_generate
    authorize PortfolioReport.new(entity_id: current_user.entity_id), :bulk_generate?

    if request.post?
      template_id  = params[:portfolio_report_template_id].to_i
      portco_ids   = Array(params[:portfolio_company_ids]).map(&:to_i).reject(&:zero?)
      start_date   = begin
        Date.parse(params[:start_date])
      rescue StandardError
        (Time.zone.today - 3.months).beginning_of_month
      end
      end_date = begin
        Date.parse(params[:end_date])
      rescue StandardError
        Time.zone.today.end_of_month
      end
      n_periods    = params[:n_periods].to_i.clamp(1, 24)
      kpi_tag      = params[:kpi_tag].presence || "Actual"
      kpi_type     = params[:kpi_period_type].presence || "Monthly"

      template = PortfolioReportTemplate.find(template_id)

      portco_ids.each do |pc_id|
        portco = Investor.find_by(id: pc_id, entity_id: current_user.entity_id)
        next unless portco

        draft = PortfolioReportDraft.create!(
          portfolio_company: portco,
          portfolio_report: template.portfolio_report,
          portfolio_report_template: template,
          user: current_user,
          start_date: start_date,
          end_date: end_date,
          kpi_period_type: kpi_type,
          kpi_tag: kpi_tag,
          n_periods: n_periods,
          selected_kpi_mapping_ids: portco.investor_kpi_mappings.show_in_report.pluck(:id),
          status: :configuring
        )
        PortfolioReportDraftJob.perform_later(draft.id)
      end

      redirect_to portfolio_reports_path,
                  notice: "Queued #{portco_ids.size} report #{'draft'.pluralize(portco_ids.size)} — you'll be notified as each completes."
    else
      # Form setup: load all portfolio companies + ready report types for this entity
      @portfolio_reports = policy_scope(PortfolioReport).includes(:portfolio_report_templates, :portfolio_report_sections)
      @ready_reports     = @portfolio_reports.select { |r| r.portfolio_report_sections.any? && r.portfolio_report_templates.any? }
      @portfolio_companies = Investor.where(entity_id: current_user.entity_id, category: "Portfolio Company").order(:investor_name)
    end
  end

  # POST /portfolio_reports/1/clone
  def clone
    authorize @portfolio_report
    copy = @portfolio_report.dup
    copy.name = "#{@portfolio_report.name} (Copy)"
    copy.save!

    @portfolio_report.portfolio_report_sections.each do |s|
      copy.portfolio_report_sections.create!(s.attributes.except("id", "portfolio_report_id", "created_at", "updated_at"))
    end

    @portfolio_report.portfolio_report_templates.each do |t|
      new_t = copy.portfolio_report_templates.create!(
        t.attributes.except("id", "portfolio_report_id", "style_document_id", "created_at", "updated_at")
          .merge("ordered_section_ids" => [])
      )
      new_t.update!(style_document: t.style_document) if t.style_document.present?
    end

    redirect_to edit_portfolio_report_path(copy), notice: "Report cloned — update the name and sections as needed."
  end

  # DELETE /portfolio_reports/1
  def destroy
    @portfolio_report.destroy!
    redirect_to portfolio_reports_url, notice: "Portfolio report was successfully destroyed.", status: :see_other
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_portfolio_report
    @portfolio_report = PortfolioReport.find(params[:id])
    authorize @portfolio_report
  end

  # Only allow a list of trusted parameters through.
  def portfolio_report_params
    params.require(:portfolio_report).permit(:entity_id, :name, :tags, :include_kpi, :include_portfolio_investments, portfolio_report_sections_attributes: %i[id name data tags icon _destroy])
  end
end
