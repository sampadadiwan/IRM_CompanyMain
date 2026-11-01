# One place that answers "what is this report column?" for the Report Builder:
# its type (money, number, date, yes/no, text), the total a related column gets
# by default, how its related data is fetched (the join strategy), and whether
# it belongs in the totals row. The engine, the formatter, the totals row, the
# wizard and the exporter all ask this class instead of guessing from key names.
#
# Worked examples H7, E2, E3, E28 — openspec/changes/report-builder-trust/design.md#worked-examples
class ReportBuilderColumnType
  # Every total a user may pick for a related column. "value" is internal only:
  # it reads the single related value of one-per-row related data (MAX of one row).
  AGGREGATES = %w[sum count avg min max latest list].freeze

  NUMERIC_TYPES = %i[money number integer].freeze

  def initialize(config)
    @config = config
    @types  = {}
  end

  # How the related data at `relation` (a dotted association path from the root)
  # is fetched:
  #   :grouped       — first-level has_many, grouped by the child's foreign key (today's path)
  #   :anchored_many — any other path that can return several rows per root row
  #   :anchored_one  — a path that returns at most one row per root row (parents, has_one)
  #   nil            — the path no longer resolves (X1)
  def strategy_for(relation)
    reflections = relation.to_s.empty? ? nil : reflections_for(relation)
    return nil if reflections.blank?

    # A single, plain has_many keeps the existing grouped-by-child path, so saved
    # related filters (Ransack on the child) keep working
    first = reflections.first
    return :grouped if reflections.size == 1 && first.macro == :has_many && !first.options[:through]

    # Anything that can fan out (has_many / habtm / through-many) returns many rows
    reflections.any?(&:collection?) ? :anchored_many : :anchored_one
  end

  # The configured join path a dotted column key belongs to: the longest relation
  # in the template's joins that prefixes the key. Falls back to the key minus its
  # last segment, so a key can be typed before its join is configured.
  def relation_for(clean_key)
    key = clean_key.to_s
    configured = config.joins.map { |j| j[:relation].to_s }
                       .select { |rel| key.start_with?("#{rel}.") }
                       .max_by(&:length)
    configured || key.split(".")[0..-2].join(".")
  end

  # The total a related column gets when none is stored (H7, E2, E28).
  # Returns nil for root columns and one-per-row related data (no total needed).
  def default_aggregate(clean_key)
    key = clean_key.to_s.split(";").first.to_s.strip
    return nil unless key.include?(".")

    strategy = strategy_for(relation_for(key))
    return nil if strategy.nil? || strategy == :anchored_one

    # An "id" column is only ever useful counted
    return "count" if key.split(".").last == "id"

    case base_type(key)
    when :money, :number, :integer then "sum"
    # Latest date / Any yes
    when :date, :datetime, :boolean then "max"
    else
      # "Latest" needs the newest row per root, which a join chain can't pick
      # cheaply — fan-out text defaults to a distinct list instead (E28)
      strategy == :anchored_many ? "list" : "latest"
    end
  end

  # The column's type after its total is applied. `column` is a
  # GridViewPreference or a ReportBuilderDynamicColumn (pivot / formula).
  def type_for(column)
    key = column_key(column)
    @types[key] ||= resolve_type(key)
  end

  # True when the column is summed in the totals row: a numeric column of the
  # root rows, or a related / pivot column totalled with Sum or Count.
  # Formula columns are recalculated from the totals instead (H18).
  def totalable?(column)
    key = column_key(column)
    return false if formula_key?(key)
    return false unless NUMERIC_TYPES.include?(type_for(column))
    return %w[sum count].include?(pivot_aggregate(key)) if pivot_key?(key)
    return true unless key.include?(".")
    return false if strategy_for(relation_for(key)) == :anchored_one

    %w[sum count].include?(config.effective_aggregate(key))
  end

  # The total a user sees in pickers, worded for the column's type
  # ("Any yes" for a yes/no maximum, "Latest date" for a date maximum).
  # Min / max labels by column kind: yes/no, dates, everything else
  EXTREME_LABELS = {
    "min" => { boolean: "All yes", date: "Earliest date", other: "Minimum" },
    "max" => { boolean: "Any yes", date: "Latest date", other: "Maximum" }
  }.freeze

  def self.aggregate_label(agg, type = nil)
    case agg.to_s
    when "sum"    then "Sum"
    when "count"  then "Count"
    when "avg"    then "Average"
    when "min", "max"
      kind = if type == :boolean then :boolean
             elsif date_type?(type) then :date
             else :other
             end
      EXTREME_LABELS[agg.to_s][kind]
    when "latest" then "Latest"
    when "list"   then "List"
    else agg.to_s.humanize
    end
  end

  def self.date_type?(type)
    %i[date datetime].include?(type)
  end

  # The column's own type before any total: from the stored column, the money
  # (`_cents`) column, or :unknown for method-only columns.
  def base_type(clean_key)
    klass, col = resolve_column(clean_key)
    return :unknown unless klass

    # Identifiers are labels, never amounts to format or total
    return :text if col == "id" || col.end_with?("_id")

    column = klass.columns_hash[col]
    if column
      case column.type
      when :integer then :integer
      when :decimal, :float then :number
      when :date then :date
      when :datetime, :timestamp, :time then :datetime
      when :boolean then :boolean
      else :text
      end
    elsif klass.columns_hash.key?("#{col}_cents")
      :money
    else
      :unknown
    end
  end

  private

  attr_reader :config

  def resolve_type(key)
    # Formula results are always numbers (formulas run on plain numbers)
    return :number if formula_key?(key)
    return after_aggregate(pivot_base_type(key), pivot_aggregate(key)) if pivot_key?(key)
    return base_type(key) unless key.include?(".")

    # One-per-row related data shows the single value as it is
    return base_type(key) if strategy_for(relation_for(key)) == :anchored_one

    after_aggregate(base_type(key), config.effective_aggregate(key))
  end

  # A total changes what a column holds: a count is a whole number, a list is
  # text, an average of whole numbers isn't whole; min/max/latest keep the type
  # (so yes/no stays yes/no — E4, E5).
  def after_aggregate(base, agg)
    case agg.to_s
    when "count" then :integer
    when "list"  then :text
    when "avg"   then base == :integer ? :number : base
    else base
    end
  end

  def column_key(column)
    key = column.respond_to?(:key) ? column.key : column.to_s
    key.to_s.split(";").first.to_s.strip
  end

  def formula_key?(key)
    config.formulas.any? { |f| f[:key].to_s == key }
  end

  def pivot_key?(key)
    key.include?("__pivot__")
  end

  def pivot_join(key)
    relation = key.split("__pivot__").first.to_s.split(".")[0..-2].join(".")
    config.join_for(relation)
  end

  def pivot_aggregate(key)
    pivot = (pivot_join(key) || {})[:pivot] || {}
    pivot[:aggregate].presence || "sum"
  end

  def pivot_base_type(key)
    base_type(key.split("__pivot__").first)
  end

  # Walks real associations from the root class along the key's path and
  # returns [model class, bare column], or nil if the path doesn't resolve.
  def resolve_column(clean_key)
    parts = clean_key.to_s.split(";").first.to_s.strip.split(".")
    col = parts.pop
    reflections = parts.empty? ? [] : reflections_for(parts.join("."))
    return nil if reflections.nil?

    klass = reflections.empty? ? config.root_class : reflections.last.klass
    [klass, col]
  rescue StandardError
    nil
  end

  # The chain of AR reflections for a dotted relation path, or nil when any
  # segment no longer exists (X1).
  def reflections_for(relation)
    klass = config.root_class
    relation.to_s.split(".").map do |part|
      reflection = klass.reflect_on_association(part.to_sym)
      return nil unless reflection

      klass = reflection.klass
      reflection
    end
  rescue StandardError
    nil
  end
end
