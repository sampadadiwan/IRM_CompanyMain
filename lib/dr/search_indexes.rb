# frozen_string_literal: true

module Dr
  # Which Elasticsearch indexes a disaster recovery rebuilds, and how to judge the result.
  #
  # Search queries Elasticsearch, which holds a DERIVED copy of selected tables and is not backed
  # up - after a DR every index is empty. The DR rebuilds each index the live app maintains, before
  # traffic is switched on, and dr:verify later proves each one holds its records
  # (openspec fix-dr-search-index-after-restore).
  #
  # Why not `rake chewy:reset`: Chewy finds indexes through `indices_path` (default app/chewy),
  # but this app keeps them in app/packs/**/models, so it finds NONE and exits 0. Even when it does
  # run it ignores import errors (RakeHelper#reset_one drops reset!'s return value).
  #
  # Pure apart from db_count / es_count, which the callers use to fetch the numbers.
  module SearchIndexes
    # Where index classes live: one `<name>_index.rb` per index inside a pack's models directory
    INDEX_GLOB = "app/packs/**/models/*_index.rb"

    # Indexes a DR deliberately does NOT rebuild, each with the reason. Restoring search means
    # restoring it AS LIVE HAS IT, and live does not maintain these.
    EXCLUDED = {
      "AccountEntryIndex" => "the live app does not maintain it (update_index is commented out in " \
                             "account_entry.rb, \"too much data\") - ~7.6M rows, 93% of all search documents"
    }.freeze

    # Verification runs after traffic is back on, so a few records may be in flight between MySQL
    # and Elasticsearch: allow 1% or 5 documents, whichever is larger.
    VERIFY_TOLERANCE_RATIO = 0.01
    VERIFY_TOLERANCE_MIN = 5

    # Same ok/warn/fail verdict dr:verify uses for the backup checks
    Grade = BackupSchedule::Grade

    module_function

    # Every Chewy index class defined under the tree, sorted by name. Discovery is by FILE, so a
    # new index is included without anyone editing a list.
    def discover(root = Rails.root)
      Dir.glob(Pathname.new(root).join(INDEX_GLOB).to_s).filter_map do |file|
        # folder_index.rb -> FolderIndex, resolved through the autoloader
        klass = File.basename(file, ".rb").camelize.safe_constantize
        klass if klass.is_a?(Class) && klass < Chewy::Index
      end.uniq.sort_by(&:name)
    end

    # The indexes a DR rebuilds and verifies.
    def indexes(root = Rails.root)
      discover(root).reject { |index| EXCLUDED.key?(index.name) }
    end

    # The indexes a DR skips, for the reindex log.
    def excluded(root = Rails.root)
      discover(root).select { |index| EXCLUDED.key?(index.name) }
    end

    # The MySQL rows an index holds: its own index_scope (e.g. FaqEntry.published), so the count
    # compares like with like.
    def db_scope(index)
      index.adapter.default_scope
    end

    def db_count(index)
      # unscope(:includes): the preloads in index_scope are for importing, not counting
      db_scope(index).unscope(:includes).count
    end

    # Does the live app keep this index current? True when its model declares update_index
    # (Chewy records each one in the model's chewy_callbacks). Six indexes have no callback and
    # were only ever refreshed by the unreferenced ElasticImporterJob, so on a LIVE environment
    # they drift - a known state, not a recovery failure.
    def maintained?(index)
      model = index.adapter.target
      model.respond_to?(:chewy_callbacks) && model.chewy_callbacks.any?
    end

    # Documents in the index right now (after a refresh, so just-imported ones are counted).
    def es_count(index)
      index.client.indices.refresh(index: index.index_name)
      index.client.count(index: index.index_name)["count"]
    end

    # exact: true right after the reindex (traffic is off, so counts must match exactly);
    # false in verification (traffic is on, so allow the tolerance above).
    # imported: what Chewy's reset! returned - false means some documents failed to import.
    # maintained: false for an index live does not keep current (see maintained?) - in verification
    # its drift is reported as a warning instead of failing the stack.
    def grade(index_name:, es:, db:, exact:, imported: true, maintained: true)
      verdict = strict_grade(index_name: index_name, es: es, db: db, exact: exact, imported: imported)
      # E6 — verification on a live environment: an unmaintained index drifting is known, not broken
      return verdict if verdict.status == :ok || exact || maintained

      Grade.new(:warn, "#{verdict.detail} (live does not keep #{index_name} current: no update_index on its model)")
    end

    def strict_grade(index_name:, es:, db:, exact:, imported:)
      # X1 — Chewy's import returns false instead of raising
      return Grade.new(:fail, "#{index_name}: import reported errors — see the Chewy output above") unless imported

      # X3 — the original bug: an empty index used to pass as a reachable one
      return Grade.new(:fail, "#{index_name}: search index empty (MySQL has #{db})") if es.zero? && db.positive?

      diff = db - es
      allowed = exact ? 0 : [VERIFY_TOLERANCE_MIN, (db * VERIFY_TOLERANCE_RATIO).ceil].max
      # H2 / H3 / E1 / E2 — within what this stage allows
      return Grade.new(:ok, "#{index_name}: #{es} of #{db}") if diff.abs <= allowed

      # X2 / X4 — missing (or unexpected extra) documents
      detail = diff.positive? ? "#{diff} missing" : "#{-diff} more than MySQL"
      Grade.new(:fail, "#{index_name}: Elasticsearch #{es} vs MySQL #{db} — #{detail}")
    end
  end
end
