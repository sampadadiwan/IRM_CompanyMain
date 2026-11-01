# One filter field of the Report Builder: what kind of input it gets, which
# operators (in plain words, each a Ransack predicate) and — for yes/no, funds
# and text fields with few values — the choices to pick from.
#
#   date     locale date input        is on / on or after / on or before / empty / not empty
#   boolean  Yes / No                  is / is empty
#   fund     the entity's funds        is / is any of
#   number   number box                is / at least / at most / is empty
#   choice   existing values (≤ 30)    is / is not / is any of / is empty
#   text     text box                  contains / is / is any of / is not / is empty
#
# Pick-lists never run on the largest tables (CLAUDE.md), and stop at 30 values.
# Worked examples H8, E7, E8, E9, E10 — openspec/changes/report-builder-live-builder/business-rules.md
class ReportBuilderFilterField
  LARGE_TABLES = %w[account_entries capital_remittances capital_distribution_payments documents].freeze
  CHOICE_LIMIT = 30
  NO_VALUE_OPS = %w[null not_null].freeze
  YES_NO = { "true" => "Yes", "false" => "No" }.freeze

  OPERATORS = {
    date: [["is on", "eq"], ["is on or after", "gteq"], ["is on or before", "lteq"], ["is empty", "null"], ["is not empty", "not_null"]],
    boolean: [["is", "eq"], ["is empty", "null"]],
    fund: [["is", "eq"], ["is any of", "in"]],
    number: [["is", "eq"], ["is at least", "gteq"], ["is at most", "lteq"], ["is empty", "null"]],
    choice: [["is", "eq"], ["is not", "not_eq"], ["is any of", "in"], ["is empty", "null"]],
    text: [["contains", "cont"], ["is", "eq"], ["is any of", "in"], ["is not", "not_eq"], ["is empty", "null"]]
  }.freeze

  attr_reader :key, :relation

  # "category_not_eq" → ["category", "not_eq"]; the longest operator wins, so
  # not_eq / not_cont / not_in / not_null aren't read as eq / cont / in / null.
  # nil op when the key has none of the known operators.
  def self.split_predicate(pred_key)
    pred_key = pred_key.to_s
    op = ReportBuilderHelper::KNOWN_OP_SUFFIXES.sort_by { |s| -s.length }.find { |s| pred_key.end_with?("_#{s}") }
    [op ? pred_key.delete_suffix("_#{op}") : pred_key, op]
  end

  # A saved filter in words — "Category is LP", "Fund is Growth Fund II" —
  # for the wizard's sentences and the health check (H24, E16)
  def self.describe(config:, entity:, pred_key:, value:, relation: nil)
    field, op = split_predicate(pred_key)
    info  = new(config: config, key: field, entity: entity, relation: relation)
    words = info.operators.find { |_, o| o == op }&.first || op
    label = ReportBuilderColumnCatalog.label_for(config, [relation, field].compact.join("."))
    return "#{label} #{words}" if NO_VALUE_OPS.include?(op)

    # Ids of a fund become its name; true / false become Yes / No
    shown = Array(value).map(&:to_s)
    shown = Fund.where(entity_id: entity.id, id: shown).pluck(:name).presence || shown if info.kind == :fund
    shown = shown.map { |v| YES_NO.fetch(v, v) } if info.kind == :boolean
    "#{label} #{words} #{shown.to_sentence(two_words_connector: ' or ', last_word_connector: ' or ')}"
  end

  def initialize(config:, key:, entity:, relation: nil)
    @config   = config
    @key      = key.to_s
    @entity   = entity
    @relation = relation.presence
  end

  def kind
    @kind ||= begin
      type = @config.column_type.base_type(full_key)
      if key == "fund_id" then :fund
      elsif %i[date datetime].include?(type) then :date
      elsif type == :boolean then :boolean
      elsif %i[money number integer].include?(type) then :number
      elsif choice_values.any? then :choice
      else :text
      end
    end
  end

  def operators
    OPERATORS[kind]
  end

  # [[label, value]] to pick from (yes/no, funds, few-valued text)
  def options
    case kind
    when :boolean then [%w[Yes true], %w[No false]]
    when :fund then Fund.where(entity_id: @entity.id).order(:name).pluck(:name, :id).map { |n, id| [n, id.to_s] }
    when :choice then choice_values.map { |v| [v.to_s, v.to_s] }
    else []
    end
  end

  # nil when the row can be saved, else what is wrong with it (E9, E10)
  def validate(op, value)
    return nil if NO_VALUE_OPS.include?(op.to_s)
    return "needs a value" if Array(value).compact_blank.empty?

    case kind
    when :date
      Date.iso8601(value.to_s)
      nil
    when :number
      Float(value.to_s)
      nil
    end
  rescue ArgumentError, TypeError
    kind == :date ? "Enter a date like #{I18n.l(Date.new(2026, 8, 19))}" : "Enter a number"
  end

  private

  def full_key
    relation ? "#{relation}.#{key}" : key
  end

  def klass
    @klass ||= relation ? ReportBuilderColumnCatalog.related_class(@config.root_class, relation) : @config.root_class
  end

  # Existing values of a text column, when there are at most 30 of them — one
  # bounded DISTINCT query on the entity's rows; never on the large tables (E7, E8)
  def choice_values
    @choice_values ||= listable? ? distinct_values : []
  end

  # A string column of an entity-scoped table that isn't one of the largest
  def listable?
    klass.present? && LARGE_TABLES.exclude?(klass.table_name) && klass.column_names.include?(key) &&
      klass.column_names.include?("entity_id") && klass.columns_hash[key].type == :string
  end

  def distinct_values
    values = klass.where(entity_id: @entity.id).where.not(key => [nil, ""])
                  .unscope(:order).distinct.limit(CHOICE_LIMIT + 1).pluck(key)
    values.size > CHOICE_LIMIT ? [] : values.sort
  end
end
