# Starting points for a Report Builder report: the template page, creating a
# new report from a starter template (with the fund it needs), and Duplicate.
# Both writes go through ReportSpecApplier, so a template or a copy is exactly
# what the builder would have saved. A template never changes an existing
# report. Worked examples H2–H10, E1–E8, X2–X5 —
# openspec/changes/report-builder-starting-points/business-rules.md
module ReportBuilder
  module Starting
    extend ActiveSupport::Concern

    TEMPLATE_UNAVAILABLE = "That template isn't available".freeze
    TEMPLATE_BROKEN      = "That template can't be used right now".freeze
    FUND_NEEDED          = "Choose a fund — this template adds up amounts".freeze
    COPY_SUFFIX_LIMIT    = 20

    # GET /report_builder/templates — the templates this company can use,
    # grouped by area (H2, E2)
    def templates
      authorize Report.new(entity: current_user.entity), :create?
      load_templates_page
    end

    # POST /report_builder/templates/:key — a new report from a template,
    # opened in the builder (H4–H8)
    def create_from_template
      authorize Report.new(entity: current_user.entity), :create?

      # X3, E2 — unknown, or uses a feature this company doesn't have
      @template = ReportBuilderTemplates.find(params[:key], current_user.entity)
      return redirect_to report_builder_templates_path, alert: TEMPLATE_UNAVAILABLE unless @template

      # X2 — only this company's funds (another company's is Not found)
      fund = Fund.where(entity_id: current_user.entity.id).find(params[:fund_id]) if params[:fund_id].present?
      # E1 — a template that adds up money needs one fund
      return refuse_missing_fund if @template["fund"] == "required" && fund.nil?

      fund = nil if @template["fund"] == "none"
      report = Report.new(user: current_user, entity: current_user.entity, curr_role: current_user.curr_role,
                          name: template_report_name(@template, fund), report_builder: true, url: "/report_builder")
      authorize report, :create?

      ReportSpecApplier.apply!(report: report, spec: @template["spec"], fund: fund)
      redirect_to edit_report_builder_path(report), notice: "Created from #{@template['name']}"
    rescue ReportSpecApplier::Invalid => e
      # X5 — nothing was saved (one transaction); the reasons go to the log
      Rails.logger.error "[ReportBuilder::Starting] #{params[:key]}: #{e.errors.join('; ')}"
      redirect_to report_builder_templates_path, alert: TEMPLATE_BROKEN
    end

    # POST /report_builder/:id/duplicate — "Copy of <name>" with the same
    # set-up, opened in the builder; no schedule, no pending Undo (H9, E4, E5)
    def duplicate
      # X4 — a report of this company only (show? also passes for shared, entity-less reports)
      authorize @report, :update?
      return redirect_back_or_to(reports_path, alert: "Only Report Builder reports can be duplicated") unless @report.report_builder?

      copy = Report.new(user: current_user, entity: current_user.entity, curr_role: current_user.curr_role,
                        name: copy_name(@report.name), description: @report.description,
                        report_builder: true, url: @report.url.presence || "/report_builder")
      authorize copy, :create?

      # Copied as it is — an imperfect report stays imperfect; the report check shows it
      ReportSpecApplier.apply!(report: copy, spec: ReportSpecApplier.spec_from(@report), validate: false)
      redirect_to edit_report_builder_path(copy), notice: "Copied from #{@report.name}"
    end

    private

    def load_templates_page
      @bread_crumbs = { Reports: reports_path, 'Start from a template': nil }
      @templates_by_area = ReportBuilderTemplates.available_for(current_user.entity)
      @funds = Fund.where(entity_id: current_user.entity.id).order(:name)
    end

    # E1 — the page again, the template's popup saying what's missing
    def refuse_missing_fund
      load_templates_page
      @fund_error_key = @template["key"]
      flash.now[:alert] = "#{@template['name']}: #{FUND_NEEDED}"
      render "report_builder/templates", status: :unprocessable_entity
    end

    # The typed name; left as the template's name (or blank) it gets the fund (H8, E6)
    def template_report_name(template, fund)
      typed = params[:name].to_s.strip
      return typed if typed.present? && typed != template["name"]

      fund ? "#{template['name']} — #{fund.name}" : template["name"]
    end

    # "Copy of LPs", or "Copy of LPs (2)", "(3)"… while the company has that name (E4)
    def copy_name(name)
      base = "Copy of #{name}"
      candidates = [base] + (2..COPY_SUFFIX_LIMIT).map { |n| "#{base} (#{n})" }
      taken = Report.where(entity_id: current_user.entity.id, name: candidates).pluck(:name)
      candidates.find { |candidate| taken.exclude?(candidate) } || "#{base} (#{Time.current.to_i})"
    end
  end
end
