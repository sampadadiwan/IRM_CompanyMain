class PortfolioReportsController < ApplicationController
  # Shown when a request reaches the server with rows the browser would have refused (see report_parts_controller.js)
  PARTS_MESSAGES = {
    template_missing: "Choose a template for every report in the list.",
    template_repeated: "Each template can be used only once in a list. Remove the repeated template.",
    template_foreign: "The selected template does not belong to the chosen report.",
    extracts_only: "Consolidated reports don't use extracts, so there is nothing to generate."
  }.freeze

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
      @ready_reports     = @portfolio_reports.select { |r| r.portfolio_report_templates.any? }
      @portfolio_companies = Investor.where(entity_id: current_user.entity_id, category: "Portfolio Company").order(:investor_name)
    end
  end

  # GET /portfolio_reports/legacy_bulk_generate — filter form + turbo-frame preview of matching portfolio companies.
  # The `<select multiple>` always lists every portfolio company for the entity; a Preview click
  # just re-syncs which ones are selected to match the current Fund/Tag/Sector filter.
  def legacy_bulk_generate
    authorize PortfolioReport.new(entity_id: current_user.entity_id), :bulk_generate?

    @portfolio_companies = current_user.entity.investors.portfolio_companies.order(:investor_name)
    @funds = Pundit.policy_scope(current_user, Fund)
    @tags_for_select = @portfolio_companies.pluck(:tag_list).compact.flat_map { |t| t.split(",") }.map(&:strip).uniq.compact_blank.sort
    @sectors_for_select = @portfolio_companies.pluck(:sector).compact.flat_map { |s| s.split(",") }.map(&:strip).uniq.compact_blank.sort

    @matching_ids = []
    if params[:previewed].present?
      matching = @portfolio_companies
      fund_ids = Array(params[:fund_ids]).compact_blank
      # Subquery instead of joins(...).distinct: MySQL rejects SELECT DISTINCT id ... ORDER BY investor_name
      # (order column not in the select list), and @portfolio_companies is already ordered by investor_name.
      matching = matching.where(id: PortfolioInvestment.where(fund_id: fund_ids).select(:portfolio_company_id)) if fund_ids.present?
      matching = matching.with_tag_list(params[:tag_list]) if params[:tag_list].present?
      matching = matching.in_sector(params[:sector]) if params[:sector].present?
      @matching_ids = matching.pluck(:id)
    end
  end

  # POST /portfolio_reports/legacy_bulk_generate_options
  # First hit (hand-off from legacy_bulk_generate, no `mode` param): render the options form for
  # the finalized portfolio_company_ids. Second hit (the options form's own submit, `mode` present):
  # actually enqueue extract-only or full-report generation for those companies.
  def legacy_bulk_generate_options
    # X11: users without access to portfolio reports are refused
    authorize PortfolioReport.new(entity_id: current_user.entity_id), :bulk_generate?

    # X10: only companies of the user's entity are used; a foreign id is dropped
    portfolio_company_ids = Array(params[:portfolio_company_ids]).map(&:to_i).reject(&:zero?)
    @portfolio_companies = Investor.where(id: portfolio_company_ids, entity_id: current_user.entity_id, category: "Portfolio Company")

    # Can't generate for nothing: bounce back to the company-selection step instead of rendering
    # an options page (or queuing a job) for zero companies.
    if @portfolio_companies.empty?
      redirect_to legacy_bulk_generate_portfolio_reports_path,
                  alert: "Select at least one portfolio company to continue." and return
    end

    if params[:mode].blank?
      @portfolio_reports = policy_scope(PortfolioReport)
      return
    end

    start_date = params[:start_date]
    end_date = params[:end_date]
    redirect_path = params[:back_to].presence || portfolio_reports_path
    # The browser already checks the rows (see report_parts_controller.js), so a refusal below only
    # happens for a tampered request. Nothing is preserved: the user starts again from the company step.
    company_step = legacy_bulk_generate_portfolio_reports_path

    # X4: each row's report is found inside the user's entity, else it is not found
    parts = report_parts

    case params[:mode]
    # generate extracts only (no full report) for the selected companies
    when "extracts_only"
      # X14: consolidated reports use no extracts, so a list of only those has nothing to generate
      normal_reports = parts.map(&:first).reject(&:consolidated?).uniq
      redirect_to company_step, alert: PARTS_MESSAGES[:extracts_only] and return if normal_reports.empty?

      # H9: one bulk job per distinct normal report; consolidated reports are ignored and a repeated report runs once
      queued = 0
      # generate extracts for companies that don't already have one for this report + date range, if the "only missing" checkbox is checked
      only_missing = params[:only_missing_extracts].present?
      normal_reports.each do |portfolio_report|
        # one query per report: the companies whose latest matching extract already has data
        done_ids = if only_missing
                     PortfolioReportExtract.where(portfolio_report_id: portfolio_report.id, portfolio_company_id: @portfolio_companies.map(&:id), start_date:, end_date:)
                                           .order(:created_at).to_a.group_by(&:portfolio_company_id)
                                           .select { |_id, extracts| extracts.last.data.present? }.keys
                   else
                     []
                   end
        company_ids = @portfolio_companies.map(&:id) - done_ids

        # One bulk job for the whole selection so the user gets a single completion message (and a
        # single error email) instead of N independent jobs that each report only themselves.
        next if company_ids.blank?

        GeneratePortfolioReportExtractsJob.perform_later(company_ids, portfolio_report.id, start_date, end_date, current_user.id)
        queued += company_ids.size
      end

      if queued.positive?
        message = if normal_reports.one?
                    "Queued extract generation for #{queued} #{'company'.pluralize(queued)}."
                  else
                    "Queued extract generation for #{queued} #{'extract'.pluralize(queued)} across #{normal_reports.size} reports."
                  end
        redirect_to redirect_path, notice: message
      else
        redirect_to redirect_path,
                    notice: "Skipped extract generation: all companies already have extracts for this report and date range."
      end
    # generate full report (with extracts if missing) for the selected companies
    when "full_report"
      # X3, X12, X13: the same checks the browser makes; the first failure wins
      if (refusal = parts_refusal(parts))
        redirect_to company_step, alert: refusal and return
      end

      # The first row stays in the job's original arguments so jobs queued across a deploy still run (E9);
      # the other rows follow in order.
      first_report, first_template_id = parts.first
      additional_parts = parts.drop(1).map { |report, template_id| { "portfolio_report_id" => report.id, "template_id" => template_id } }
      PortfolioReportJob.perform_later(
        first_report.id, first_template_id, start_date, end_date, current_user.id,
        portfolio_company_ids: @portfolio_companies.pluck(:id),
        generate_missing_extracts: params[:generate_missing_extracts].present?,
        additional_parts:
      )
      redirect_to redirect_path,
                  notice: "Queued report generation for #{@portfolio_companies.size} #{'company'.pluralize(@portfolio_companies.size)}."
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
    @bread_crumbs = { "Portfolio Reports" => portfolio_reports_path, @portfolio_report.name => portfolio_report_path(@portfolio_report) }
  end

  # The rows of the options page, in the order the user sees them, as [PortfolioReport, template_id] pairs.
  # E6: rows are read in the order of their numbers, which may have gaps (a removed row leaves one).
  # E8: a request with one report and one template in the earlier form is a list of one row.
  def report_parts
    rows = if params[:parts].respond_to?(:each_pair)
             params[:parts].each_pair.sort_by { |index, _| index.to_i }.filter_map do |_, row|
               row.permit(:portfolio_report_id, :report_template_id) if row.respond_to?(:permit)
             end
           else
             [params.permit(:portfolio_report_id, :report_template_id)]
           end
    rows.map do |row|
      [policy_scope(PortfolioReport).find(row[:portfolio_report_id]), row[:report_template_id].presence&.to_i]
    end
  end

  # The first reason the list cannot be generated, or nil. Checked in this order: every row has a
  # template (X12), no template is used twice (X13), every template belongs to its row's report (X3).
  # A request with no rows at all is refused like a row without a template.
  def parts_refusal(parts)
    template_ids = parts.map(&:last)
    return PARTS_MESSAGES[:template_missing] if parts.empty? || template_ids.any?(&:blank?)
    return PARTS_MESSAGES[:template_repeated] if template_ids.uniq.size != template_ids.size
    return PARTS_MESSAGES[:template_foreign] unless parts.all? { |report, template_id| report.documents.exists?(id: template_id) }

    nil
  end

  # Only allow a list of trusted parameters through.
  def portfolio_report_params
    params.require(:portfolio_report).permit(:entity_id, :name, :tags, :include_kpi, :include_portfolio_investments, :consolidated, portfolio_report_sections_attributes: %i[id name data tags icon _destroy])
  end
end
