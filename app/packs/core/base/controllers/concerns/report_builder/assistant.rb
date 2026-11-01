# "Describe it": a report from a question. The Describe page takes the
# question; a private draft report holds the assistant's state (template "ai");
# ReportDraftJob drafts it in the background. The draft page shows guided
# setup's cards, the AI's questions, assumptions and couldn't-do, the preview
# and a chart, and saves, fine-tunes or discards the draft.
#
# Privacy of drafts lives in ReportPolicy (only their maker sees them).
# Worked examples H1–H9, E1–E12, X1–X7 — openspec/changes/report-builder-assistant/business-rules.md
module ReportBuilder
  module Assistant
    extend ActiveSupport::Concern

    DRAFT_CATEGORY = "AI draft".freeze
    # X6 — a draft still drafting this recently doesn't start another conversation
    BUSY_FOR = 2.minutes
    CHART_KINDS = %w[suggested none].freeze

    # GET /report_builder/describe (H1, X4)
    def describe
      authorize Report.new(entity: current_user.entity), :create?
      @available = ReportDraftGenerator.available?(current_user.entity)
      @examples  = ReportBuilderTemplates.available_for(current_user.entity).values.flatten.pluck("question")
      @drafts    = policy_scope(Report).where(category: DRAFT_CATEGORY, user_id: current_user.id).order(updated_at: :desc)
      @bread_crumbs = { Reports: reports_path, 'Describe your report': nil }
    end

    # POST /report_builder/describe — saves a private draft and drafts it in the background (H2)
    def describe_create
      authorize Report.new(entity: current_user.entity), :create?
      question = params[:question].to_s.strip
      return redirect_to(report_builder_describe_path, alert: "AI drafting isn't set up for your account") unless ReportDraftGenerator.available?(current_user.entity)
      return redirect_to(report_builder_describe_path(question: question), alert: "Describe the report in 5 to 1,000 characters") unless question.length.between?(5, 1000)

      report = Report.create!(entity: current_user.entity, user: current_user, curr_role: current_user.curr_role,
                              name: "Draft — #{question.truncate(40, omission: '')}", category: DRAFT_CATEGORY,
                              report_builder: true, url: "/report_builder",
                              template: { "draft" => true, "ai" => { "question" => question, "status" => "drafting",
                                                                     "started_at" => Time.current.iso8601 } })
      ReportDraftJob.perform_later(report.id, current_user.id)
      redirect_to report_builder_draft_path(report)
    end

    # GET /report_builder/:id/draft
    def draft
      authorize @report, :update?
      return redirect_to(view_report_builder_path(@report)) unless assistant_draft?

      @bread_crumbs = { Reports: reports_path, 'Describe your report': report_builder_describe_path, @report.name => nil }
      load_draft_state
    end

    # GET /report_builder/:id/draft/state — the draft's frame, reloaded after the job finishes
    def draft_state
      authorize @report, :update?
      load_draft_state
      render partial: "report_builder/draft_state"
    end

    # POST /report_builder/:id/draft/refine — an instruction, or an answer to the AI's question (H4, E5, X6)
    def draft_refine
      authorize @report, :update?
      # X1 — "Draft again" after a failure retries the last ask
      if params[:retry].present?
        start_drafting(ai_state["turns"].to_a.last&.dig("instruction")) unless drafting?
        return render_draft_state
      end

      instruction = params[:instruction].to_s.strip
      instruction = "Answer to \"#{params[:answer_to]}\": #{instruction}" if params[:answer_to].present?
      unless instruction.length.between?(3, 600)
        flash.now[:alert] = "Say what to change in 3 to 500 characters"
        return render_draft_state(:unprocessable_entity)
      end

      start_drafting(instruction) unless drafting?
      render_draft_state
    end

    # POST /report_builder/:id/draft/fund — no AI call: the fund goes where guided setup puts it (H3)
    def draft_fund
      authorize @report, :update?
      fund = Fund.where(entity_id: current_user.entity_id).find(params[:fund_id])
      return render_draft_state(:unprocessable_entity) unless @report.grid_view_preferences.exists?

      spec = ReportSpecApplier.spec_from(@report)
      strip_fund_filters(spec)
      update_ai("fund_id" => fund.id, "questions" => ai_state["questions"].to_a.reject { |q| q["kind"] == "pick_fund" })
      ReportSpecApplier.apply!(report: @report, spec: spec, fund: fund, validate: false, replace: true)
      render_draft_state
    end

    # PATCH /report_builder/:id/draft/chart — the suggested chart or none (H5, H7)
    def draft_chart
      authorize @report, :update?
      kind = params[:kind].to_s.presence_in(CHART_KINDS) || "suggested"
      @report.update!(template: @report.template.merge("chart" => { "kind" => kind }))
      render_draft_state
    end

    # POST /report_builder/:id/draft/chart — "Describe a chart": the 20 preview rows go to the AI (H8)
    def draft_describe_chart
      authorize @report, :update?
      load_preview_state
      rows = @rows.map { |row| @columns.to_h { |col| [col.label.presence || col.name, @formatter.display(row[col.key], col)] } }
      spec = ChartAgentService.new(json_data: rows, entity: current_user.entity).generate_chart!(prompt: params[:prompt].to_s)
      chart = AgentChart.create!(entity: current_user.entity, report_id: @report.id, owner: @report, title: params[:prompt].to_s.truncate(60),
                                 prompt: params[:prompt].to_s, spec: spec, status: "ready")
      @report.update!(template: @report.template.merge("chart" => { "kind" => "agent", "agent_chart_id" => chart.id }))
      render_draft_state
    rescue StandardError => e
      Rails.logger.warn("[ReportBuilder::Assistant] chart failed: #{e.message}")
      flash.now[:alert] = "Couldn't draw that chart — try describing it differently"
      render_draft_state(:unprocessable_entity)
    end

    # PATCH /report_builder/:id/draft/save — no longer a draft; the question is its description (H6, H9)
    def draft_save
      authorize @report, :update?
      name = params[:name].to_s.strip.presence || ai_state["name"].presence || @report.name.delete_prefix("Draft — ")
      # The chart the draft page showed is the one kept (suggested, unless changed)
      chart = @report.template["chart"] || { "kind" => "suggested" }
      @report.update!(name: name, category: nil, description: ai_state["question"],
                      template: @report.template.except("draft").merge("ai" => ai_state.slice("question", "turns"), "chart" => chart))
      return redirect_to(edit_report_builder_path(@report), notice: "Saved #{name}") if params[:fine_tune].present?

      redirect_to view_report_builder_path(@report), notice: "Saved #{name}"
    end

    # DELETE /report_builder/:id/draft (E8)
    def draft_discard
      authorize @report, :update?
      @report.destroy!
      redirect_to report_builder_describe_path, notice: "Draft discarded"
    end

    private

    def assistant_draft?
      @report.category == DRAFT_CATEGORY
    end

    def ai_state
      (@report.template || {})["ai"] || {}
    end

    def drafting?
      ai_state["status"] == "drafting" && Time.zone.parse(ai_state["started_at"].to_s).to_i > BUSY_FOR.ago.to_i
    end

    def update_ai(changes)
      @report.update!(template: @report.template.merge("ai" => ai_state.merge(changes)))
    end

    def start_drafting(instruction)
      update_ai("status" => "drafting", "started_at" => Time.current.iso8601, "error" => nil)
      ReportDraftJob.perform_later(@report.id, current_user.id, instruction)
    end

    # The AI never picks a fund; a chosen fund replaces any fund filter
    def strip_fund_filters(spec)
      spec["root_filters"] = (spec["root_filters"] || {}).except("fund_id_eq")
      Array(spec["joins"]).each { |j| j["child_filters"] = (j["child_filters"] || {}).except("fund_id_eq") }
    end

    def load_draft_state
      @report.reload
      @ai = ai_state
      load_builder_state
      return unless @root_class

      @gvps = @report.grid_view_preferences.reorder(:sequence, :id).to_a
      @funds = Fund.where(entity_id: current_user.entity_id).order(:name).pluck(:name, :id)
      # The preview's 20 rows, shown in the page and used for the suggested chart
      load_preview_state if @gvps.any?
    end

    def render_draft_state(status = :ok)
      load_draft_state
      render partial: "report_builder/draft_state", status: status
    end
  end
end
