# Orchestrates the two-pass query strategy:
#   Pass 1 – root model query (Ransack filters + sort + entity scoping)
#   Pass 2 – one aggregator per join (pivot or regular)
# Then merges results into an array of hashes keyed by column key.
class ReportBuilderQueryEngine
  # Safety ceiling for the "sort by a computed column" path below — a sort key
  # that isn't a plain root-model column (a joined/aggregate/pivot/formula
  # value) can only be applied after pass2 has computed it for every row, so
  # pagination can't happen in SQL. We still cap how many root rows we'll ever
  # pull into memory for that path, so a report rooted on a huge table (e.g.
  # AccountEntry) with a computed sort key can't materialize the whole table.
  MAX_COMPUTED_SORT_ROWS = 20_000

  # M16 — the rows a report shows are the rows `user` may see: pass1 starts from the user's Pundit
  # scope of the root model, and each joined relation's aggregates count only the children in the
  # user's scope of that model. Before, a fund-restricted employee's report read every KYC, commitment
  # or user of the firm. Callers pass the person the rows are for: the viewer on screen, the requester
  # of an on-demand export, the report's owner for a scheduled one (ReportBuilderExportJob).
  # docs/security/security_review_2026_10.md (M16 row); tests M16-1, M16-2, M16-H —
  # features/security/security_review_2026_10_medium.feature
  # sort_override: { key:, dir: } from a clicked column header on the report
  # page — used for this run only, never saved; ignored unless the key is one
  # of the report's own columns (RD4: H20, X4)
  def initialize(report:, entity:, user:, external_filters: {}, sort_override: nil)
    @report           = report
    @entity           = entity
    @user             = user
    @config           = ReportBuilderConfig.new(report.template)
    @external_filters = (external_filters || {}).with_indifferent_access
    @dynamic_columns  = []
    @sort_override    = valid_sort_override(sort_override)
  end

  # True when the last run sorted by a computed column and hit the row cap,
  # so the page can say "Sorted within the first N rows" (E23)
  # The columns a pivot on first-level related data would create, over this
  # report's rows (its filters included) — for the pivot form's preview (H16, X2)
  def pivot_preview(relation, group_bys, value_col)
    return { error: "Pivots work on related data with many rows per row" } unless column_type.strategy_for(relation) == :grouped

    reflection = config.root_class.reflect_on_association(relation.to_sym)
    join_cfg   = (config.join_for(relation) || {}).merge(
      relation: relation, mode: :grouped, base_class: reflection.klass, fk: reflection.foreign_key.to_s, joins: nil,
      poly_type: reflection.type, poly_name: (config.root_class.polymorphic_name if reflection.type),
      pivot: { group_bys: Array(group_bys), value_col: value_col.to_s, aggregate: "sum" }
    )
    ReportBuilderPivotAggregator.new(join_config: join_cfg, root_ids: root_scope.select(:id), user: user).preview_columns
  end

  # The report's rows as a scope (entity, filters, only-with-rows) — for the
  # health check's bounded counts
  def rows_scope
    root_scope
  end

  # The related rows behind the report's rows, with the related data's own
  # filters — first-level many-per-row related data only (health check H15)
  def related_scope(relation)
    reflection = config.root_class.reflect_on_association(relation.to_sym)
    related = reflection.klass.where(reflection.foreign_key => root_scope.select(:id))
    # M16 — only the related rows the user may see, as the aggregates count them
    visible = self.class.visible_ids(user, reflection.klass)
    related = related.where(id: visible) if visible
    related = related.where(reflection.type => config.root_class.polymorphic_name) if reflection.type
    filters = ((config.join_for(relation) || {})[:child_filters] || {}).with_indifferent_access
    filters.present? ? related.ransack(filters).result : related
  end

  def computed_sort_capped?
    @computed_sort_capped == true
  end

  # The sort in effect: a valid header override, else the saved one
  def effective_sort
    @sort_override || { key: sort_key, dir: sort_dir }
  end

  # Returns Array<Hash> where each hash is one output row.
  # limit/offset page the *root* query (pass1) in SQL — the cheap, default path.
  # computed_sort_cap bounds how many rows the "sort by a computed column" path
  # (below) will ever pull into memory; pass nil to leave it truly unbounded —
  # ReportBuilderExportJob does this, since a download must return every row
  # regardless of sort, not just the first MAX_COMPUTED_SORT_ROWS.
  def run(limit: nil, offset: nil, computed_sort_cap: MAX_COMPUTED_SORT_ROWS)
    return [] unless config.valid?

    @dynamic_columns = []

    # A sort key that isn't a real root-model column (e.g. a joined/aggregate
    # GridViewPreference like "capital_commitments.amount") only exists after
    # merge — apply_sort silently can't order the SQL scope by it. Rather than
    # keep dropping the sort on the floor, compute the (capped) full dataset,
    # sort it in memory, then slice out the requested page.
    return run_with_computed_sort(limit: limit, offset: offset, cap: computed_sort_cap) if computed_sort?

    root_records, root_ids = pass1(limit: limit, offset: offset)
    child_data              = pass2(root_ids)
    rows                    = merge(root_records, child_data)

    apply_formulas(rows)
  end

  # Row count without loading all data (for preview badge).
  def count
    return 0 unless config.valid?

    root_scope.count
  end

  # M16 — the ids of `klass` rows `user` may see, as a subquery for a joined relation's aggregates, so
  # out-of-scope children are left out even as a count or sum (M16-2). A subquery rather than the scope
  # itself: a scope's own joins would repeat child rows under GROUP BY and inflate a SUM. A model with
  # no Pundit scope answers nil and keeps the children of the (already scoped) root rows, as before.
  def self.visible_ids(user, klass)
    # Pundit's own lookup (KlassPolicy::Scope, inherited ones included); nil when the model has no
    # policy (checked first: with no policy the finder would look up a top-level ::Scope)
    finder = Pundit::PolicyFinder.new(klass)
    scope_class = finder.policy && finder.scope
    return nil unless scope_class

    # Only the id column, with no ORDER BY, so it can sit inside IN (...) (CLAUDE.md, unscope(:order))
    scope_class.new(user, klass.all).resolve.unscope(:order).reselect(klass.arel_table[:id])
  end

  # GVP columns + any dynamic pivot columns + formula columns.
  # Position rows ("formula:<key>", "pivot:<relation>") become the formula
  # column or the pivot's block of columns at that place; formulas and pivots
  # without a position row (reports saved before positions existed) follow all
  # other columns as before: pivots, then formulas. Worked examples H10, H11, E7.
  def columns
    formula_cols = (config.formulas || []).to_h do |f|
      [f["key"].to_s, ReportBuilderDynamicColumn.new(key: f["key"], label: f["label"])]
    end
    pivot_cols = @dynamic_columns.group_by { |c| column_type.relation_for(c.key.split("__pivot__").first) }

    placed_formulas = []
    placed_pivots   = []
    ordered = gvp_columns.flat_map do |gvp|
      if gvp.key.start_with?("formula:")
        key = gvp.key.delete_prefix("formula:")
        placed_formulas << key
        Array(formula_cols[key])
      elsif gvp.key.start_with?("pivot:")
        relation = gvp.key.delete_prefix("pivot:")
        placed_pivots << relation
        pivot_cols[relation] || []
      else
        [gvp]
      end
    end

    ordered + pivot_cols.except(*placed_pivots).values.flatten + formula_cols.except(*placed_formulas).values
  end

  private

  attr_reader :report, :entity, :user, :config

  # M16 — the root rows this report may list: the user's Pundit scope of the root model, narrowed to
  # the report's entity. Chained with where (never merge, which would let the scope's own entity_id
  # condition replace this one). The scope's ORDER BY is dropped: pass1 applies the report's sort, and
  # a DISTINCT scope would refuse an ORDER BY outside its select list on MySQL (M16-1, M16-H)
  def visible_roots
    Pundit.policy_scope!(user, config.root_class).unscope(:order).where(entity_id: entity.id)
  end

  # Fetches every row up to the safety cap (unbounded pass1/pass2 within that
  # cap), sorts by the computed key, then hands back just the requested page —
  # the only way to sort correctly by a value that only exists post-merge.
  def run_with_computed_sort(limit:, offset:, cap:)
    root_records, root_ids = pass1(limit: cap)
    @computed_sort_capped   = cap.present? && root_records.size >= cap
    child_data              = pass2(root_ids)
    rows                    = apply_formulas(merge(root_records, child_data))
    rows                    = sort_rows(rows)
    paginate_rows(rows, limit: limit, offset: offset)
  end

  # True when the configured sort key is not a plain column on the root
  # model — i.e. it can only be resolved after pass2/merge (a joined column,
  # an aggregate, a pivot column, or a formula result).
  def computed_sort?
    key = sort_key
    key.present? && config.root_class.column_names.exclude?(key)
  end

  def sort_key
    return @sort_override[:key] if @sort_override

    config.sort[:key].to_s.split(";").first&.strip.to_s
  end

  def sort_dir
    return @sort_override[:dir] if @sort_override

    config.sort[:dir] == "desc" ? "desc" : "asc"
  end

  # A header sort is only used when it names one of the report's own columns
  # (a selected column, a formula, or a configured pivot's column); anything
  # else is ignored and the saved sort applies (X4)
  def valid_sort_override(override)
    return nil if override.blank?

    key = override[:key].to_s.split(";").first.to_s.strip
    return nil if key.blank?

    own_keys = gvp_columns.map { |g| g.key.split(";").first.strip }.reject { |k| k.start_with?("formula:", "pivot:") } +
               config.formulas.map { |f| f[:key].to_s }
    pivot_ok = key.include?("__pivot__") && config.join_for(key.split("__pivot__").first.split(".")[0..-2].join("."))
    return nil unless own_keys.include?(key) || pivot_ok

    { key: key, dir: override[:dir].to_s == "desc" ? "desc" : "asc" }
  end

  # In-memory equivalent of apply_sort for keys apply_sort can't reach.
  # Groups nils first (stable across rows lacking the aggregate/formula value)
  # and falls back to leaving order untouched if values aren't comparable.
  def sort_rows(rows)
    key = sort_key
    return rows if key.blank?

    # Row hashes are keyed by the raw GridViewPreference key, which usually
    # carries a "; col-type" suffix (e.g. "capital_commitments.amount; num-col")
    # — but `key` here is always the clean, suffix-stripped form. Resolve back
    # to whichever raw key produced this sort_key so the lookup below actually
    # hits instead of silently missing on every row (leaving rows unsorted).
    row_key = columns.find { |c| c.key.split(";").first.strip == key }&.key || key

    sorted = begin
      rows.sort_by { |r| [r[row_key].nil? ? 0 : 1, r[row_key]] }
    rescue ArgumentError
      rows
    end

    sort_dir == "desc" ? sorted.reverse : sorted
  end

  def paginate_rows(rows, limit:, offset:)
    return rows unless limit

    rows[offset.to_i, limit] || []
  end

  def apply_formulas(rows)
    formulas = config.formulas
    return rows if formulas.blank?

    service = ReportBuilderFormulaService.new(formulas)
    rows.map { |row| service.evaluate(row) }
  end

  # ── Pass 1 ──────────────────────────────────────────────────────────────

  # The report's own rows: this entity only, its filters, and — for joins with
  # "only rows that have …" — just the rows with at least one matching related
  # row (respecting that join's related filters). Shared by #run and #count so
  # the row count always matches the rows. Worked examples H13, H14, E11.
  def root_scope
    # M16 — from the rows the user may see (their Pundit scope of the root)
    scope = visible_roots
    scope = scope.ransack(config.root_filters.merge(@external_filters)).result

    config.joins.each do |join_cfg| # rubocop:disable Rails/FindEach -- config.joins is a plain Array, not an AR::Relation
      relation = join_cfg[:relation].to_s
      next unless config.only_with_rows?(relation) && column_type.strategy_for(relation) == :grouped

      reflection = config.root_class.reflect_on_association(relation.to_sym)
      related    = reflection.klass.all
      # M16 — "has a related row" counts only related rows the user may see
      visible    = self.class.visible_ids(user, reflection.klass)
      related    = related.where(id: visible) if visible
      related    = related.where(reflection.type => config.root_class.polymorphic_name) if reflection.type
      filters    = (join_cfg[:child_filters] || {}).with_indifferent_access
      related    = related.ransack(filters).result if filters.present?
      # IN (subquery) — the related ids never come into Ruby
      scope = scope.where(id: related.select(reflection.foreign_key))
    end

    scope
  end

  def pass1(limit: nil, offset: nil)
    scope = apply_sort(root_scope)

    # Preload what decorator-style readers need, so a 20k-row export doesn't
    # run one query per row for e.g. Investing Entity (H6)
    preloads = ReportBuilderColumnCatalog.preloads_for(config.root_class, root_column_keys)
    scope = scope.includes(*preloads) if preloads.any?

    scope = scope.limit(limit) if limit
    # SQL-level OFFSET keeps paginated pages from re-loading earlier rows —
    # only used by run() for the plain-column-sort fast path.
    scope = scope.offset(offset) if offset

    records = scope.to_a
    [records, records.map(&:id)]
  end

  # Clean keys of the selected columns that live on the root rows
  def root_column_keys
    columns.map { |c| c.key.split(";").first.strip }.reject { |k| k.include?(".") }
  end

  def apply_sort(scope)
    key = sort_key
    dir = sort_dir == "desc" ? "DESC" : "ASC"
    return scope unless key.present? && config.root_class.column_names.include?(key)

    # Qualified with the root's table: the user's scope may join tables that share the column name
    column = config.root_class.arel_table[key]
    scope.order(dir == "DESC" ? column.desc : column.asc)
  end

  # ── Pass 2 ──────────────────────────────────────────────────────────────

  def pass2(root_ids)
    return {} if root_ids.empty?

    config.joins.each_with_object({}) do |join_cfg, acc|
      relation_path = join_cfg[:relation].to_s
      strategy      = column_type.strategy_for(relation_path)

      # A saved path that no longer resolves leaves its columns blank (X1)
      unless strategy
        Rails.logger.warn "[ReportBuilder] unresolvable relation #{relation_path} report=#{report.id}"
        next
      end

      # Columns belonging to this join: the join is the longest configured
      # relation prefixing the key, so "capital_commitments.fund.name" goes to
      # "capital_commitments.fund", not "capital_commitments" (H4)
      gvp_keys = gvp_columns.map(&:key).select { |k| column_type.relation_for(k.split(";").first.strip) == relation_path }

      if strategy == :grouped
        acc[relation_path] = grouped_join_data(join_cfg, relation_path, root_ids, gvp_keys)
      elsif gvp_keys.any?
        acc[relation_path] = anchored_join_data(join_cfg, relation_path, strategy, root_ids, gvp_keys)
      end
    end
  end

  # First-level has_many: query the child table grouped by its foreign key
  # (the original path — related filters and pivots apply). H5, H12.
  def grouped_join_data(join_cfg, relation_path, root_ids, gvp_keys)
    reflection  = config.root_class.reflect_on_association(relation_path.to_sym)
    join_config = join_cfg.merge(mode: :grouped, base_class: reflection.klass, fk: reflection.foreign_key.to_s, joins: nil,
                                 poly_type: reflection.type, poly_name: (config.root_class.polymorphic_name if reflection.type))

    pivot_cfg = join_cfg[:pivot]
    pivot_ready = pivot_cfg.present? &&
                  Array(pivot_cfg[:group_bys] || pivot_cfg[:group_by]).any?(&:present?) &&
                  pivot_cfg[:value_col].to_s.present?

    if pivot_ready
      dyn_cols, pivot_data = ReportBuilderPivotAggregator.new(join_config: join_config, root_ids: root_ids, user: user).call
      @dynamic_columns.concat(dyn_cols)
      return pivot_data
    end
    return {} if gvp_keys.empty?

    ReportBuilderChildAggregator.new(join_config: join_config, root_ids: root_ids,
                                     aggregates: build_rel_aggregates(gvp_keys), gvp_keys: gvp_keys, user: user).call
  end

  # Parents, has_one, through and multi-step paths: query the root table joined
  # along the path, grouped by the root id. One-per-row data reads its single
  # value; fan-out data uses the column's total. H1, H2, H3, E1.
  def anchored_join_data(join_cfg, relation_path, strategy, root_ids, gvp_keys)
    aggregates = if strategy == :anchored_one
                   gvp_keys.to_h { |k| [k.split(";").first.strip, "value"] }
                 else
                   build_rel_aggregates(gvp_keys)
                 end

    ReportBuilderChildAggregator.new(
      join_config: join_cfg.merge(mode: :anchored, base_class: config.root_class, fk: "id", joins: relation_path),
      root_ids: root_ids, aggregates: aggregates, gvp_keys: gvp_keys, user: user
    ).call
  end

  def build_rel_aggregates(gvp_keys)
    gvp_keys.each_with_object({}) do |key, h|
      clean = key.split(";").first.strip
      # Stored total, else the type default (E3)
      agg   = config.effective_aggregate(clean)
      h[clean] = agg if agg
    end
  end

  def column_type
    config.column_type
  end

  def gvp_columns
    @gvp_columns ||= report.grid_view_preferences.reorder(:sequence, :id).to_a
  end

  def resolve_fk(root_class, relation_name, join_cfg)
    return join_cfg[:fk] if join_cfg[:fk].present?

    reflection = root_class.reflect_on_association(relation_name.to_sym)
    return "#{root_class.name.underscore}_id" unless reflection

    case reflection.macro
    when :has_many, :has_one then reflection.foreign_key.to_s
    when :belongs_to         then "id"
    else "#{root_class.name.underscore}_id"
    end
  end

  # ── Merge ───────────────────────────────────────────────────────────────

  def merge(root_records, child_data)
    all_cols = columns # GVPs + dynamic pivot columns

    root_records.map do |root|
      all_cols.each_with_object({}) do |col, row|
        clean = col.key.split(";").first.strip

        if clean.include?(".")
          # Results are stored under the join's full path, so look the key up
          # under the longest configured relation that prefixes it (H4, EN7)
          relation   = column_type.relation_for(clean)
          rel_result = child_data[relation] || {}
          row_data   = rel_result[root.id]

          if col.is_a?(ReportBuilderDynamicColumn)
            # Pivot key is the full col.key (includes __pivot__ value)
            row[col.key] = row_data ? (row_data[col.key] || 0) : 0
          elsif column_type.strategy_for(relation) == :anchored_one
            # One-per-row data: the value, or blank when the parent is missing (E1)
            row[col.key] = row_data&.[](clean)
          else
            agg_type     = config.effective_aggregate(clean)
            row[col.key] = row_data ? row_data[clean] : zero_value(agg_type)
          end
        else
          # The record's own attribute/method, else the catalog's plain-text
          # reader for decorator-only columns (H6); errors read as blank (X6)
          row[col.key] = ReportBuilderColumnCatalog.read(root, clean)
        end
      end
    end
  end

  def zero_value(agg_type)
    %w[sum count].include?(agg_type) ? 0 : nil
  end
end
