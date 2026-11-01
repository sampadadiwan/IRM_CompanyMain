# The guided wizard ("Guided setup"): the original step-by-step front door
# onto the same Report#template the builder writes — name and table, then
# Columns → Related Data → Summarize → Filters → Sort → Review. Each step uses
# the builder's own actions (add_column, add_join, update_aggregate,
# update_sort …); only the filter form has its own two small actions.
#
# Restored after the five-step rework was judged harder to use; on top of the
# original: an example question for every table, "Guided setup" naming, the
# Summarize total shown is the one saved and used (W1), and Review's
# "Open My Report" opens the report page (W11).
module ReportBuilder
  module Wizard
    extend ActiveSupport::Concern

    WIZARD_STEPS = %w[columns joins aggregates filters sort review].freeze
    # Steps a wizard form can name in params[:wizard_step] (BuilderUpdates#wizard_request?)
    WIZARD_STEP_KEYS = WIZARD_STEPS

    # Icon + example question for each table on the first page
    WIZARD_MODEL_META = {
      "Investor" => { icon: "ti-users", example: "Which LPs still have KYC pending?" },
      "Fund" => { icon: "ti-building-bank", example: "How much has each fund called vs. collected?" },
      "InvestorKyc" => { icon: "ti-shield-check", example: "Who is flagged for AML review?" },
      "CapitalCommitment" => { icon: "ti-file-text", example: "List every commitment with its called amount." },
      "CapitalCall" => { icon: "ti-phone-outgoing", example: "Which calls are still short of their due amount?" },
      "CapitalRemittance" => { icon: "ti-cash", example: "Which remittances are still pending?" },
      "CapitalRemittancePayment" => { icon: "ti-receipt-2", example: "Which payments came in this quarter?" },
      "CapitalDistributionPayment" => { icon: "ti-arrow-back-up", example: "How much fee was deducted from each distribution?" },
      "CapitalDistribution" => { icon: "ti-cash-banknote", example: "How much has each fund distributed, and when?" },
      "PortfolioInvestment" => { icon: "ti-briefcase", example: "Which investments were bought or sold this year?" },
      "AggregatePortfolioInvestment" => { icon: "ti-chart-pie", example: "What does each fund hold in each company today?" },
      "AccountEntry" => { icon: "ti-book-2", example: "What fees and income were allocated to each LP?" },
      "FundUnit" => { icon: "ti-chart-bar", example: "How many units has each LP been issued?" },
      "CommitmentAdjustment" => { icon: "ti-adjustments", example: "Which commitments were adjusted, and by how much?" },
      "ExchangeRate" => { icon: "ti-currency-dollar", example: "Which rates were used for each currency pair?" },
      "KpiReport" => { icon: "ti-report", example: "Which companies have sent their KPIs this quarter?" },
      "Kpi" => { icon: "ti-chart-line", example: "How has revenue moved for each company?" },
      "Document" => { icon: "ti-file", example: "Which documents are still waiting for signatures?" }
    }.freeze
    WIZARD_DEFAULT_ICON = "ti-table".freeze

    # Acronyms `.underscore.humanize` can't know about ("Investor kyc" → "Investor KYC")
    WIZARD_LABEL_ACRONYMS = { "Kyc" => "KYC", "Kpi" => "KPI", "Aml" => "AML" }.freeze

    # Plain-language explanation + a tiny example for each way of combining
    # related rows — tooltips next to the picker on the Summarize step
    WIZARD_AGGREGATE_HELP = {
      "sum" => { label: "Sum", blurb: "Adds every value together.", example: "3 commitments of ₹10L, ₹20L, ₹5L → ₹35L" },
      "count" => { label: "Count", blurb: "Counts how many rows there are — the column itself doesn't matter.", example: "3 commitments → 3" },
      "avg" => { label: "Average", blurb: "The arithmetic mean of the values.", example: "₹10L, ₹20L, ₹5L → ₹11.7L" },
      "min" => { label: "Minimum", blurb: "The smallest value.", example: "Commitment dates → the earliest one" },
      "max" => { label: "Maximum", blurb: "The largest value.", example: "Call due dates → the most recent one" },
      "latest" => { label: "Latest", blurb: "The value from the single most recent row.", example: "3 KYC records → the newest one's status" },
      "list" => { label: "List", blurb: "A comma-separated list of every distinct value.", example: "Unit types → \"Class A, Class B\"" }
    }.freeze

    # Model class names are PascalCase ("CapitalCommitment"), so plain
    # `.humanize` makes one run-together word; `.underscore` first splits it.
    def self.model_label(model_name)
      label = model_name.to_s.underscore.humanize
      WIZARD_LABEL_ACRONYMS.reduce(label) { |l, (from, to)| l.gsub(/\b#{from}\b/i, to) }
    end

    included do
      helper_method :wizard_model_label, :wizard_icon_for, :wizard_example_for, :wizard_type_icon_for, :wizard_aggregate_help
    end

    # GET /report_builder/wizard — name the report and pick the table it starts from
    def wizard_new
      authorize Report.new(entity: current_user.entity), :create?
      @bread_crumbs = { Reports: reports_path, 'Guided setup': nil }
      @root_models = ReportBuilderModelDiscovery.roots.group_by { |m| ReportBuilderModelDiscovery.pack_for(m) }
      render "report_builder/wizard/new"
    end

    # POST /report_builder/wizard — creates the report, then opens the Columns step
    def wizard_create
      @report = Report.new(
        user: current_user, entity: current_user.entity, curr_role: current_user.curr_role,
        name: params[:name].to_s.strip.presence || "Untitled Report",
        report_builder: true, url: "/report_builder",
        template: { version: 1, root_model: params[:root_model], joins: [], aggregates: {}, root_filters: {}, sort: {} }
      )
      authorize @report, :create?

      if @report.save
        redirect_to wizard_report_builder_step_path(@report, step: "columns")
      else
        redirect_to wizard_report_builder_path, alert: @report.errors.full_messages.to_sentence
      end
    end

    # GET /report_builder/:id/wizard/:step — columns, joins, aggregates, filters, sort, review
    def wizard_step
      authorize @report, :update?

      step = params[:step].to_s
      return redirect_to wizard_report_builder_step_path(@report, step: "columns") unless WIZARD_STEPS.include?(step)

      load_builder_state
      return redirect_to wizard_report_builder_path, alert: "That report's root model could not be loaded." unless @root_class

      # No related data yet — Summarize has nothing to show, so go straight past it
      return redirect_to wizard_report_builder_step_path(@report, step: "filters") if step == "aggregates" && @config.joins.empty?

      @bread_crumbs = { Reports: reports_path, @report.name => view_report_builder_path(@report), 'Guided setup': nil }
      @joined_columns = @config.joins.each_with_object({}) do |j, h|
        klass = ReportBuilderColumnCatalog.related_class(@root_class, j[:relation].to_s)
        h[j[:relation].to_s] = ReportBuilderColumnCatalog.related_columns_for(klass) if klass
      end
      @gvps = @report.grid_view_preferences.reorder(:sequence, :id).to_a

      render "report_builder/wizard/#{step}"
    end

    # POST /report_builder/:id/wizard_filter — one filter row (field, operator,
    # value) from the Filters step, stored as the builder stores it ("field_op")
    def wizard_add_filter
      authorize @report, :update?

      field = params[:field].to_s.strip
      op    = params[:op].to_s.strip.presence || "eq"
      value = params[:value].to_s.strip
      return redirect_to wizard_report_builder_step_path(@report, step: "filters") if field.blank?

      pred_val = op == "in" ? value.split(",").map(&:strip).compact_blank : value
      pred_val = "1" if ReportBuilderFilterField::NO_VALUE_OPS.include?(op)
      wizard_update_filters(params[:relation].to_s.strip.presence) { |filters| filters.merge("#{field}_#{op}" => pred_val) }

      redirect_to wizard_report_builder_step_path(@report, step: "filters")
    end

    # DELETE /report_builder/:id/wizard_filter — removes one filter by its key
    def wizard_remove_filter
      authorize @report, :update?

      wizard_update_filters(params[:relation].to_s.strip.presence) { |filters| filters.except(params[:pred_key].to_s) }
      redirect_to wizard_report_builder_step_path(@report, step: "filters")
    end

    private

    def wizard_model_label(model_name)
      ReportBuilder::Wizard.model_label(model_name)
    end

    def wizard_icon_for(model_name)
      WIZARD_MODEL_META.dig(model_name.to_s, :icon) || WIZARD_DEFAULT_ICON
    end

    def wizard_example_for(model_name)
      WIZARD_MODEL_META.dig(model_name.to_s, :example)
    end

    def wizard_aggregate_help
      WIZARD_AGGREGATE_HELP
    end

    # Icon for one column in the pickers: the "; col-type" hint when there is
    # one, else the real column's type (root and "relation.field" keys alike)
    def wizard_type_icon_for(raw_key)
      key = raw_key.to_s
      return "ti-hash" if key.include?("num-col")
      return "ti-calendar" if key.include?("date-col")
      return "ti-tag" if key.include?("label-col")

      column = @report&.model_columns_hash&.[](key.split(";").first.strip)
      case column&.type
      when :integer, :decimal, :float then "ti-hash"
      when :date, :datetime then "ti-calendar"
      when :boolean then "ti-toggle-left"
      else "ti-abc"
      end
    rescue StandardError
      "ti-abc"
    end

    # Yields the root filters (relation nil) or one related data's filters and saves the result
    def wizard_update_filters(relation)
      tmpl = (@report.reload.template || {}).deep_stringify_keys
      if relation.nil?
        tmpl["root_filters"] = yield(tmpl["root_filters"] || {})
      else
        tmpl["joins"] = (tmpl["joins"] || []).map do |join|
          join["relation"] == relation ? join.merge("child_filters" => yield(join["child_filters"] || {})) : join
        end
      end
      @report.update!(template: tmpl)
    end
  end
end
