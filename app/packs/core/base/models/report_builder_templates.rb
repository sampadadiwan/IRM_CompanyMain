# The Report Builder's starter templates (config/report_builder_templates.yml):
# loaded once, listed per company and found by key. A template is listed only
# when every table it uses — the report's own and each related data's —
# belongs to a feature the company has (Funds, Deals…), the same rule the
# column pickers use. Worked examples H2, E2, X3 —
# openspec/changes/report-builder-starting-points/business-rules.md
class ReportBuilderTemplates
  PATH = Rails.root.join("config/report_builder_templates.yml")

  # Area keys in page order, with their headings
  AREAS = {
    "investors" => "Investors", "capital_calls" => "Capital calls", "distributions" => "Distributions",
    "fund_overview" => "Fund overview", "portfolio" => "Portfolio", "compliance" => "Compliance"
  }.freeze

  FUND_CHOICES = %w[required optional none].freeze

  class << self
    # { "lp_capital_account" => { "key", "name", "area", "question", "includes", "fund", "spec" }, … }
    def all
      @all ||= YAML.safe_load_file(PATH).to_h { |key, template| [key, template.merge("key" => key).freeze] }.freeze
    end

    # { "Investors" => [template, …], … } in area order, only templates the entity can use
    def available_for(entity)
      usable = all.values.select { |template| usable?(template, entity) }
      AREAS.filter_map do |area, heading|
        templates = usable.select { |t| t["area"] == area }
        [heading, templates] if templates.any?
      end.to_h
    end

    # The template, or nil when it doesn't exist or isn't available to the entity
    def find(key, entity)
      template = all[key.to_s]
      template if template && usable?(template, entity)
    end

    # Tests swap in a broken copy of a template (X1, X5); reset puts the file back
    def reset!
      @all = nil
    end

    def override!(key, template)
      @all = all.merge(key.to_s => template.merge("key" => key.to_s).freeze).freeze
    end

    private

    # Every table the template uses belongs to a feature the entity has (E2)
    def usable?(template, entity)
      tables_of(template["spec"]).all? { |klass| klass && ReportBuilderModelDiscovery.pack_enabled_for?(klass, entity) }
    end

    def tables_of(spec)
      root = spec["root_model"].to_s.safe_constantize
      return [nil] unless root

      [root] + Array(spec["joins"]).map { |join| ReportBuilderColumnCatalog.related_class(root, join["relation"]) }
    end
  end
end
