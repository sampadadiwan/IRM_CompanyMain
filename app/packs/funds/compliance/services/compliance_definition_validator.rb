# ① Validates a pack version's definition JSON against ComplianceDataCatalog.
# Returns a list of error messages naming the offending key (X1–X7, X63, E3–E5).
# Nothing in the definition is evaluated — only checked against fixed lists.
# Worked examples H2, H3, H7, H9, H10, E3, E4, E5, X1–X7, X63 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceDefinitionValidator
  MEASURE_OPS = %w[sum count count_distinct max min expr input].freeze
  EXPR_OPS = %w[+ - * / min max].freeze
  CHECK_KINDS = %w[limit record_document manual].freeze
  COMPARES = %w[lte lt gte gt eq].freeze
  UNITS = %w[pct amount count].freeze
  TESTED = %w[continuous on_record].freeze
  OVERRIDES = %w[stricter_only none any].freeze
  SEVERITIES = %w[breach warning needs_review].freeze
  SCHEDULES = %w[quarterly half_yearly yearly].freeze
  PERIOD_BASES = %w[fy_apr calendar].freeze
  INPUT_TYPES = %w[investor_group fund_figure document].freeze
  MAX_TIME_TO_FIX = 365

  def self.call(definition, caphive: false)
    new(definition, caphive:).errors
  end

  def initialize(definition, caphive:)
    @d = definition.is_a?(Hash) ? definition : {}
    @caphive = caphive
    @errors = []
  end

  def errors
    validate_top
    validate_inputs
    validate_measures
    validate_checks
    validate_duties
    @errors.uniq
  end

  private

  def classifications
    Array(@d["classifications"]).map(&:to_s)
  end

  def measure_keys
    Array(@d["measures"]).filter_map { |m| m["key"] }
  end

  def input_keys
    Array(@d["inputs"]).filter_map { |i| i["key"] }
  end

  # X1: at least one classification
  def validate_top
    @errors << "Add at least one classification" if classifications.empty?
    pb = @d["period_basis"]
    @errors << "Unknown period basis: #{pb}" if pb.present? && PERIOD_BASES.exclude?(pb)
  end

  def validate_inputs
    Array(@d["inputs"]).each do |i|
      @errors << "Input needs a key" if i["key"].blank?
      @errors << "Unknown input type: #{i['type']}" if INPUT_TYPES.exclude?(i["type"].to_s)
    end
  end

  # X5: unknown field / source / op named in the error
  def validate_measures
    Array(@d["measures"]).each do |m|
      key = m["key"]
      @errors << "Measure needs a key" if key.blank?
      op = m["op"].to_s
      next @errors << "Unknown operation: #{op} (#{key})" if MEASURE_OPS.exclude?(op)

      case op
      when "expr" then validate_expr(m["expr"], key)
      when "input" then @errors << "Unknown input: #{m['input']}" if input_keys.exclude?(m["input"])
      else validate_source_measure(m, key)
      end
    end
    validate_cycles
  end

  def validate_source_measure(measure, key)
    src = measure["source"].to_s
    return @errors << "Unknown source: #{src}" unless ComplianceDataCatalog.source?(src)

    @errors << "Unknown field: #{measure['field']}" if %w[sum max min count_distinct].include?(measure["op"]) && !ComplianceDataCatalog.field?(src, measure["field"])
    @errors << "Unknown grouping: #{measure['group_by']} (#{key})" if measure["group_by"].present? && !ComplianceDataCatalog.group?(src, measure["group_by"])
    Array(measure["filters"]).each { |f| validate_filter(src, f) }
  end

  def validate_filter(src, filter)
    field, op, = filter
    @errors << "Unknown filter operation: #{op}" if ComplianceDataCatalog::FILTER_OPS.exclude?(op.to_s)
    return if ComplianceDataCatalog::SPECIAL_FILTERS.include?(field.to_s) || ComplianceDataCatalog.field?(src, field)

    @errors << "Unknown field: #{field}"
  end

  def validate_expr(expr, key)
    return if expr.is_a?(Numeric)
    return @errors << "Unknown measure: #{expr} (#{key})" if expr.is_a?(String) && measure_keys.exclude?(expr)
    return unless expr.is_a?(Array)

    @errors << "Unknown operator: #{expr.first} (#{key})" if EXPR_OPS.exclude?(expr.first.to_s)
    expr.drop(1).each { |e| validate_expr(e, key) }
  end

  # LLD reviewer check: a measure referencing itself through others is refused
  def validate_cycles
    graph = Array(@d["measures"]).to_h { |m| [m["key"], expr_refs(m["expr"])] }
    graph.each_key do |start|
      stack = graph[start].dup
      seen = {}
      while (k = stack.pop)
        next if seen[k]

        seen[k] = true
        if k == start
          @errors << "Measure #{start} refers to itself"
          break
        end
        stack.concat(graph[k] || [])
      end
    end
  end

  def expr_refs(expr)
    case expr
    when String then [expr]
    when Array then expr.drop(1).flat_map { |e| expr_refs(e) }
    else []
    end
  end

  def validate_checks
    Array(@d["checks"]).each do |c|
      key = c["key"].presence || c["name"]
      @errors << "Check needs a key" if c["key"].blank?
      @errors << "Unknown check kind: #{c['kind']}" if CHECK_KINDS.exclude?(c["kind"].to_s)
      # X2 / H7: citation required on CapHive packs only
      @errors << "Citation is required" if @caphive && c["citation"].blank?
      validate_applies_to(c)
      validate_check_common(c, key)
      case c["kind"]
      when "limit" then validate_limit_check(c, key)
      when "record_document" then validate_document_check(c)
      end
    end
  end

  # X3 / E5
  def validate_applies_to(check)
    applies = check["applies_to"]
    return if applies.nil? || applies == "all"

    Array(applies).each do |cl|
      @errors << "Unknown classification: #{cl}" if classifications.exclude?(cl.to_s)
    end
  end

  # E3 / X4: time to fix 0–365
  def validate_check_common(check, _key)
    ttf = check["time_to_fix_days"]
    @errors << "Time to fix must be 0–365 days" if !ttf.nil? && !(ttf.is_a?(Integer) && ttf.between?(0, MAX_TIME_TO_FIX))
    @errors << "Unknown tested setting: #{check['tested']}" if check["tested"].present? && TESTED.exclude?(check["tested"])
    @errors << "Unknown override policy: #{check['override']}" if check["override"].present? && OVERRIDES.exclude?(check["override"])
    @errors << "Unknown severity: #{check['severity']}" if check["severity"].present? && SEVERITIES.exclude?(check["severity"])
  end

  def validate_limit_check(check, key)
    validate_expr(check["figure"], key)
    @errors << "Unknown comparison: #{check['compare']}" if COMPARES.exclude?(check["compare"].to_s)
    limit = check["limit"].is_a?(Hash) ? check["limit"] : {}
    @errors << "Unknown unit: #{limit['unit']}" if UNITS.exclude?(limit["unit"].to_s)
    @errors << "Limit is required (#{key})" if limit["value"].nil? && limit["expr"].nil?
    validate_expr(limit["expr"], key) if limit["expr"]
  end

  # X6: record-level document checks need a checks-from date
  def validate_document_check(check)
    @errors << "Unknown source: #{check['source']}" unless ComplianceDataCatalog.source?(check["source"].to_s)
    @errors << "Checks from date is required" if check["checks_from"].blank?
    @errors << "Unknown input: #{check['document_input']}" if input_keys.exclude?(check["document_input"])
    Array(check["filters"]).each { |f| validate_filter(check["source"], f) }
  end

  # X7 / H10 / X63
  def validate_duties
    Array(@d["duties"]).each do |duty|
      trig = duty["trigger"].is_a?(Hash) ? duty["trigger"] : {}
      if trig["schedule"].present?
        @errors << "Unknown schedule: #{trig['schedule']}" if SCHEDULES.exclude?(trig["schedule"])
        @errors << "Due rule is required" if duty["due"].blank?
      elsif trig["event"].present?
        @errors << "From date is required" if trig["from"].blank?
        @errors << "Due rule is required" if duty["due"].blank?
      end
      validate_applies_to(duty)
    end
  end
end
