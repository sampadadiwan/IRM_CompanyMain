# The guided wizard: five short steps onto the same Report#template the
# builder writes, built from the builder's own parts (column picker, filter
# fields, health check, preview).
#
#   1 Each row               wizard_new / wizard_create — a card per table
#   2 What to show           step "show" — own and related columns, totals inline
#   3 Fund and filters       step "fund_filters" — fund picker, filters read back as sentences
#   4 Order and calculations step "order" — sort, suggested calculations
#   5 Check and save         step "check" — summary cards, health, sample, name
#
# Links to the old six steps still work: they redirect to the step that
# replaced them. Worked examples H18–H30, E21–E26, X4, X5 —
# openspec/changes/report-builder-live-builder/business-rules.md
module ReportBuilder
  module Wizard
    extend ActiveSupport::Concern

    WIZARD_STEPS = [
      { key: "show", label: "What to show" },
      { key: "fund_filters", label: "Fund and filters" },
      { key: "order", label: "Order and calculations" },
      { key: "check", label: "Check and save" }
    ].freeze
    WIZARD_STEP_KEYS = WIZARD_STEPS.pluck(:key).freeze

    # E26 — bookmarks of the old steps land on the step that replaced them
    OLD_WIZARD_STEPS = {
      "columns" => "show", "joins" => "show", "aggregates" => "show",
      "filters" => "fund_filters", "sort" => "order", "review" => "check"
    }.freeze

    # Icon + an example question for every table in step 1 (H18)
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

    UNKNOWN_TABLE = "Choose one of the listed tables".freeze

    # Model class names are PascalCase ("CapitalCommitment"), so plain
    # `.humanize` makes one run-together word; `.underscore` first splits it.
    def self.model_label(model_name)
      label = model_name.to_s.underscore.humanize
      WIZARD_LABEL_ACRONYMS.reduce(label) { |l, (from, to)| l.gsub(/\b#{from}\b/i, to) }
    end

    included do
      helper_method :wizard_model_label, :wizard_icon_for, :wizard_example_for, :wizard_steps
    end

    # GET /report_builder/wizard — step 1: a card per table, each with an
    # example question; choosing one creates the report (H18)
    def wizard_new
      authorize Report.new(entity: current_user.entity), :create?
      @bread_crumbs = { Reports: reports_path, 'Guided setup': nil }
      @root_models = ReportBuilderModelDiscovery.roots.group_by { |m| ReportBuilderModelDiscovery.pack_for(m) }
      render "report_builder/wizard/new"
    end

    # POST /report_builder/wizard — creates "Untitled <table> report" and opens
    # step 2; the name is suggested at the end (H19). An unknown table creates
    # nothing (X4).
    def wizard_create
      authorize Report.new(entity: current_user.entity), :create?

      root = ReportBuilderModelDiscovery.roots.find { |klass| klass.name == params[:root_model].to_s }
      return redirect_to wizard_report_builder_path, alert: UNKNOWN_TABLE unless root

      @report = Report.new(
        user: current_user, entity: current_user.entity, curr_role: current_user.curr_role,
        name: params[:name].to_s.strip.presence || "Untitled #{wizard_model_label(root.name)} report",
        report_builder: true, url: "/report_builder",
        template: { version: 1, root_model: root.name, joins: [], aggregates: {}, root_filters: {}, sort: {} }
      )
      authorize @report, :create?

      if @report.save
        redirect_to wizard_report_builder_step_path(@report, step: "show")
      else
        redirect_to wizard_report_builder_path, alert: @report.errors.full_messages.to_sentence
      end
    end

    # GET /report_builder/:id/wizard/:step — steps 2–5 (show, fund_filters,
    # order, check); old step names redirect (E26)
    def wizard_step
      authorize @report, :update?

      step = params[:step].to_s
      return redirect_to wizard_report_builder_step_path(@report, step: OLD_WIZARD_STEPS[step]) if OLD_WIZARD_STEPS.key?(step)
      return redirect_to wizard_report_builder_step_path(@report, step: "show") unless WIZARD_STEP_KEYS.include?(step)

      load_builder_state
      return redirect_to wizard_report_builder_path, alert: "That report's table could not be loaded." unless @root_class

      @step = step
      @bread_crumbs = { Reports: reports_path, @report.name => view_report_builder_path(@report), 'Guided setup': nil }
      @gvps = @report.grid_view_preferences.reorder(:sequence, :id).to_a
      load_wizard_step_state(step)
      render "report_builder/wizard/#{step}"
    end

    # POST /report_builder/:id/wizard_filter — one filter from step 3's form.
    # `field` is a root field, or "<relation>.<field>" for related data.
    def wizard_add_filter
      authorize @report, :update?

      config = ReportBuilderConfig.new(@report.template)
      relation, field = wizard_split_field(config, params[:field].to_s.strip)
      return redirect_to wizard_report_builder_step_path(@report, step: "fund_filters") if field.blank?

      filter = ReportBuilderFilterField.new(config: config, key: field, entity: current_user.entity, relation: relation)
      op     = filter.operators.map(&:last).include?(params[:op].to_s) ? params[:op].to_s : filter.operators.first.last
      value  = wizard_filter_value(op, params[:value])
      # A row that can't be saved says why (E9, E10)
      if (problem = filter.validate(op, value))
        return redirect_to wizard_report_builder_step_path(@report, step: "fund_filters", field: params[:field]),
                           alert: "#{ReportBuilderColumnCatalog.label_for(config, [relation, field].compact.join('.'))} #{problem}"
      end

      wizard_update_filters(relation) { |filters| filters.merge("#{field}_#{op}" => value) }
      redirect_to wizard_report_builder_step_path(@report, step: "fund_filters")
    end

    # DELETE /report_builder/:id/wizard_filter — removes one filter by its key
    def wizard_remove_filter
      authorize @report, :update?

      wizard_update_filters(params[:relation].to_s.strip.presence) { |filters| filters.except(params[:pred_key].to_s) }
      redirect_to wizard_report_builder_step_path(@report, step: "fund_filters")
    end

    # POST /report_builder/:id/wizard_fund — step 3's fund picker: limits the
    # report's own rows when they have a fund, else each related data with a
    # fund; blank means All funds (H23, E22)
    def wizard_fund
      authorize @report, :update?

      fund = params[:fund_id].present? ? Fund.where(entity_id: current_user.entity.id).find(params[:fund_id]) : nil
      config = ReportBuilderConfig.new(@report.template)
      targets = ReportBuilderFundTarget.for(config)
      set_fund = ->(filters) { fund ? filters.merge("fund_id_eq" => fund.id.to_s) : filters.except("fund_id_eq") }

      if targets[:root]
        wizard_update_filters(nil, &set_fund)
      else
        targets[:relations].each { |relation| wizard_update_filters(relation, &set_fund) }
      end

      redirect_to wizard_report_builder_step_path(@report, step: "fund_filters"), notice: fund ? "Only #{fund.name}" : "All funds"
    end

    # PATCH /report_builder/:id/wizard_save — names the report (the suggested
    # name when left blank) and opens its report page (H29, E25)
    def wizard_save
      authorize @report, :update?

      gvps = @report.grid_view_preferences.reorder(:sequence, :id).to_a
      name = params[:name].to_s.strip.presence ||
             ReportBuilderSuggestions.name(ReportBuilderConfig.new(@report.template), gvps, current_user.entity)
      @report.update!(name: name)
      redirect_to view_report_builder_path(@report), notice: "Saved #{name}"
    end

    private

    def wizard_steps
      WIZARD_STEPS
    end

    def wizard_model_label(model_name)
      ReportBuilder::Wizard.model_label(model_name)
    end

    def wizard_icon_for(model_name)
      WIZARD_MODEL_META.dig(model_name.to_s, :icon) || WIZARD_DEFAULT_ICON
    end

    def wizard_example_for(model_name)
      WIZARD_MODEL_META.dig(model_name.to_s, :example)
    end

    # What each step shows besides the shared builder state
    def load_wizard_step_state(step)
      case step
      when "fund_filters"
        @fund_targets = ReportBuilderFundTarget.for(@config)
        @funds = Fund.where(entity_id: current_user.entity.id).order(:name) if @fund_targets[:root] || @fund_targets[:relations].any?
        @current_fund_id = wizard_current_fund_id(@config, @fund_targets)
        @filter_field = params[:field].presence
      when "order"
        @suggestions = ReportBuilderSuggestions.for(@config, @gvps)
      when "check"
        @suggested_name = ReportBuilderSuggestions.name(@config, @gvps, current_user.entity)
      end
    end

    def wizard_current_fund_id(config, targets)
      return config.root_filters["fund_id_eq"].presence if targets[:root]

      targets[:relations].filter_map { |relation| (config.join_for(relation)[:child_filters] || {}).stringify_keys["fund_id_eq"] }.first
    end

    # "capital_commitments.unit_type" → ["capital_commitments", "unit_type"]
    # when capital_commitments is many-per-row related data; else [nil, field]
    def wizard_split_field(config, raw)
      relation = config.joins.map { |j| j[:relation].to_s }
                       .select { |rel| raw.start_with?("#{rel}.") && config.column_type.strategy_for(rel) == :grouped }
                       .max_by(&:length)
      relation ? [relation, raw.delete_prefix("#{relation}.")] : [nil, raw]
    end

    # The value as the filter stores it: "1" for empty / not empty, a list for "is any of"
    def wizard_filter_value(op, raw)
      return "1" if ReportBuilderFilterField::NO_VALUE_OPS.include?(op)
      return Array(raw).flat_map { |v| v.to_s.split(",") }.map(&:strip).compact_blank if op == "in"

      Array(raw).first.to_s.strip
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
