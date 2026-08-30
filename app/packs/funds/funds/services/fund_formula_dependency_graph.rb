# Builds the field-level dependency graph between a fund's FundFormulas -- which
# formula produces which computed field(s), and which later formulas read them via
# an "@field_name" reference. This mirrors the scan
# AccountEntryAllocation::RunFormulas performs before a real allocation run (see
# FundFormula#referenced_field_names and RunFormulas#configure_commitment_cache_dependencies)
# to decide what AccountEntryAllocation::CommitmentCache should keep -- but here it's
# for display, not caching.
#
# Only covers the common "one formula produces one or more named fields" rule types
# (default single name, meta_data account_entry_names override, and
# GenerateAccountEntryMultiple's names array). A handful of rule types compute a
# value without ever routing through CreateAccountEntry (so can never be a
# "producer" here), or override the rollup name at runtime (AllocatePortfolioInvestment
# and friends) -- those simply won't show a produced-field edge, same as they'd never
# populate CommitmentCache either.
class FundFormulaDependencyGraph
  Edge = Struct.new(:producer, :consumer, :field_name, keyword_init: true)

  # Modernize stat-card accent (Bootstrap color name + Tabler icon) per rule type, so
  # different kinds of formulas read as visually distinct at a glance. Anything not
  # listed here (the common case) falls back to :info/currency-dollar.
  NODE_STYLE_BY_RULE_TYPE = {
    "Percentage" => { color: "primary", icon: "percentage" },
    "GenerateAccountEntryMultiple" => { color: "secondary", icon: "stack-2" },
    "GenerateCustomField" => { color: "warning", icon: "adjustments" }
  }.freeze
  DEFAULT_NODE_STYLE = { color: "info", icon: "currency-dollar" }.freeze
  BROKEN_NODE_STYLE = { color: "danger", icon: "alert-triangle" }.freeze

  # A formula reference that can't actually resolve at runtime (evaluates to nil, silently):
  # :no_producer     -- nothing produces field_name, and it isn't one of CommitmentCache's
  #                      always-available BASE_FIELDS. Usually a typo or a deleted/renamed formula.
  # :runs_before_producer -- every formula that produces field_name runs at or after this
  #                      formula's own sequence position, so the cache hasn't been populated yet.
  BrokenReference = Struct.new(:formula, :field_name, :reason, keyword_init: true)

  attr_reader :formulas, :edges

  def initialize(formulas)
    @formulas = formulas.to_a
    @edges = build_edges
  end

  def isolated?(formula)
    connected_formula_ids.exclude?(formula.id)
  end

  def broken_references
    @broken_references ||= build_broken_references
  end

  # Formulas with no dependency edge at all: nothing reads what they produce, and they
  # read nothing produced in this run. On a large fund these are the bulk of the
  # formulas and they stack up as a tall column of disconnected cards, so the page
  # hides them behind a toggle by default.
  #
  # A formula with a broken reference stays visible even when it is isolated -- it is a
  # problem to surface, not noise to tuck away, and it is isolated precisely *because*
  # the value it reads has no producer.
  def hidden_formulas
    @hidden_formulas ||= begin
      broken_ids = broken_references.to_set { |ref| ref.formula.id }
      formulas.select { |formula| isolated?(formula) && broken_ids.exclude?(formula.id) }
    end
  end

  def visible_formulas
    @visible_formulas ||= begin
      hidden_ids = hidden_formulas.to_set(&:id)
      formulas.reject { |formula| hidden_ids.include?(formula.id) }
    end
  end

  # formula.id -> formula source text, for the view to hand to the page's Stimulus
  # controller as a data value. The controller shows this in a custom hover tooltip
  # it positions itself -- Mermaid's click-directive syntax can't carry a tooltip
  # alongside a `call callback(args)` invocation, and Mermaid's own DOM id scheme for
  # nodes isn't part of its public contract, so we don't rely on it for hover either.
  def tooltip_text_by_formula_id
    formulas.index_by(&:id).transform_values { |formula| formula.formula.to_s.gsub(/\s+/, " ").strip.truncate(500) }
  end

  # Mermaid flowchart source: one node per formula, one edge per (producer, field,
  # consumer) triple. Each node's "label" is actually a real Modernize stat-card
  # (see #node_html) rendered via Mermaid's htmlLabels support -- plain SVG
  # rects/text can't reproduce that look, so we hand Mermaid literal HTML instead and
  # let it measure/position it like any other label. Every node still carries a
  # `click ... call` directive so the page's Stimulus controller can load that
  # formula's details into a side panel -- see
  # app/javascript/controllers/fund_formula_dependency_graph_controller.js. Edge
  # labels are real Bootstrap badges (see #edge_label_html) the same way.
  #
  # Everything embedded here uses single-quoted HTML attributes and has any literal
  # double quote stripped (via #sanitize_label) -- Mermaid's own label quoting uses
  # double quotes, so an embedded `"` would terminate it early and break parsing.
  #
  # Pass a subset to render only those formulas -- the page uses this to leave the
  # isolated ones out of the default diagram (see #visible_formulas).
  def to_mermaid(included_formulas = formulas)
    included_ids = included_formulas.to_set(&:id)
    broken_formula_ids = broken_references.to_set { |ref| ref.formula.id }
    lines = ["flowchart LR"]

    included_formulas.each do |formula|
      lines << "  f#{formula.id}[\"#{node_html(formula, broken: broken_formula_ids.include?(formula.id))}\"]"
    end

    edges.each do |edge|
      next unless included_ids.include?(edge.producer.id) && included_ids.include?(edge.consumer.id)

      lines << "  f#{edge.producer.id} -->|\"#{edge_label_html(edge.field_name)}\"| f#{edge.consumer.id}"
    end

    lines.join("\n")
  end

  private

  # The Modernize stat-card markup, used as-is apart from two inline styles. Both have
  # to be inline rather than in the stylesheet: Mermaid measures an HTML label by
  # rendering it in a hidden container appended to <body>, outside this page's wrapper
  # element, so a rule scoped under .fund-formula-dependency-graph wouldn't apply during
  # measurement, and the node would be sized from different styling than it renders with.
  #   width:      pins the card size; without it Mermaid measures the card's natural
  #               width and then clips it once a stylesheet width kicks in at render.
  #   white-space: Mermaid puts nowrap on its own label wrapper, which the card would
  #               inherit -- long formula names then overflow the card instead of
  #               wrapping inside it. Set here (white-space inherits) so the card and
  #               its text wrap, and the measured height matches the rendered one.
  #   font-size:  the text is bumped above the theme defaults (sized for a dashboard
  #               tile, not a diagram node), while the icon and card padding are pulled
  #               well below them -- a full display-6 icon and dashboard-sized padding
  #               are mostly empty space here, and shrinking them buys back diagram width
  #               without costing any text legibility. Inline for the same reason as the
  #               above: measuring at one size and rendering at another means clipping.
  def node_html(formula, broken:)
    style = broken ? BROKEN_NODE_STYLE : NODE_STYLE_BY_RULE_TYPE.fetch(formula.rule_type, DEFAULT_NODE_STYLE)

    <<~HTML.squish
      <div class='card border-end border-#{style[:color]} mb-0' style='width:250px;white-space:normal;'>
        <div class='card-body' style='padding:0.75rem 0.9rem;'>
          <div class='d-flex align-items-center'>
            <div>
              <span class='text-#{style[:color]} display-6' style='font-size:1.6rem;line-height:1;'><i class='ti ti-#{style[:icon]}'></i></span>
            </div>
            <div class='ms-auto text-end'>
              <h4 class='card-title fs-7 mb-1' style='font-size:1.4rem;'>#{formula.sequence}</h4>
              <p class='card-subtitle text-#{style[:color]} mb-0' style='font-size:1rem;'>#{sanitize_label(formula.name)}</p>
            </div>
          </div>
        </div>
      </div>
    HTML
  end

  def edge_label_html(field_name)
    "<span class='badge rounded-pill bg-secondary-subtle text-secondary'>#{sanitize_label(field_name)}</span>"
  end

  # Every formula id at either end of an edge. Memoised because #isolated? is asked
  # once per formula, and rescanning the whole edge list each time would be quadratic.
  def connected_formula_ids
    @connected_formula_ids ||= edges.flat_map { |edge| [edge.producer.id, edge.consumer.id] }.to_set
  end

  def producers_by_field
    @producers_by_field ||= begin
      index = Hash.new { |hash, key| hash[key] = [] }
      formulas.each do |formula|
        produced_field_names(formula).each { |name| index[name] << formula }
      end
      index
    end
  end

  def build_edges
    formulas.each_with_object([]) do |formula, result|
      formula.referenced_field_names.each do |field_name|
        producers_by_field[field_name].each do |producer|
          next if producer == formula

          result << Edge.new(producer:, consumer: formula, field_name:)
        end
      end
    end
  end

  def build_broken_references
    formula_index = formulas.each_with_index.to_h

    formulas.each_with_object([]) do |formula, result|
      formula.referenced_field_names.each do |field_name|
        next if AccountEntryAllocation::CommitmentCache::BASE_FIELDS.include?(field_name)
        next if AccountEntryAllocation::AllocationBaseOperation::ENGINE_PROVIDED_FIELDS.include?(field_name)

        producers = producers_by_field[field_name].reject { |producer| producer == formula }

        if producers.empty?
          result << BrokenReference.new(formula:, field_name:, reason: :no_producer)
        elsif producers.all? { |producer| formula_index[producer] >= formula_index[formula] }
          result << BrokenReference.new(formula:, field_name:, reason: :runs_before_producer)
        end
      end
    end
  end

  # Field name(s) this formula's computed AccountEntry(ies) would be cached under --
  # mirrors CommitmentCache's cache key, to_varable_name(account_entry.name).
  def produced_field_names(formula)
    names = if formula.rule_type == "GenerateAccountEntryMultiple"
              formula.multiple_entry_prefixed_names
            else
              account_entry_names = formula.meta_data_hash["account_entry_names"]&.split(",")&.map(&:strip) if formula.meta_data_hash.present?
              account_entry_names.presence || [formula.name]
            end

    names.map { |name| FundFormula.to_varable_name(name) }
  end

  def sanitize_label(text)
    text.to_s.tr('"', "'").truncate(40)
  end
end
