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

    # Where the background rebuild records its progress: Rails.cache, which is solid_cache (MySQL)
    # on deployed stacks, so every app server and the Sidekiq worker see the same record.
    STATUS_KEY = "dr:search_rebuild"
    STATUS_TTL = 7 * 24 * 3600
    # A recorded rebuild speaks for the index only for a day; after that dr:verify counts instead
    STATUS_FRESH_SECONDS = 24 * 3600

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

    # The indexes to rebuild: all the DR owns, or just the named ones (ONLY=FolderIndex,FundIndex).
    def select(only = [])
      names = Array(only).map { |name| name.to_s.strip }.reject(&:empty?)
      return indexes if names.empty?

      unknown = names - indexes.map(&:name)
      raise ArgumentError, "Not a DR search index: #{unknown.join(', ')} (known: #{indexes.map(&:name).join(', ')})" if unknown.any?

      indexes.select { |index| names.include?(index.name) }
    end

    # Rebuilds one index and grades it. reset! builds a fresh suffixed index, imports into it,
    # then swaps the alias - readers never see a half-built index - and returns false (does not
    # raise) when documents fail to import. exact: true when traffic is off (the blocking rake
    # task); false in the background job, where users may be writing while it runs.
    def reindex_one(index, exact:)
      imported = index.reset!((Time.now.to_f * 1000).round, apply_journal: false)
      grade(index_name: index.name, es: es_count(index), db: db_count(index), imported: imported,
            exact: exact, maintained: maintained?(index))
    rescue StandardError => e
      # One broken index must not stop the others (AmlReportIndex, 2026-11-08)
      Grade.new(:fail, "#{index.name}: #{e.class}: #{e.message.lines.first&.strip}")
    end

    # Rebuilds each index in turn. Returns [[name, grade, seconds]]; on_progress gets
    # (number done, that row) after each one.
    def rebuild!(indexes, exact:, on_progress: nil)
      indexes.each_with_index.map do |index, i|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        row = [index.name, reindex_one(index, exact: exact),
               (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)]
        on_progress&.call(i + 1, row)
        row
      end
    end

    # --- The background rebuild's progress record -----------------------------------------------

    def read_status
      Rails.cache.read(STATUS_KEY)
    end

    def write_status(status)
      Rails.cache.write(STATUS_KEY, status, expires_in: STATUS_TTL)
    end

    # Queues the background rebuild (SearchReindexJob on the chewy queue) and records it as
    # queued. Safe while Sidekiq is stopped: the job waits in Redis until Sidekiq starts.
    def enqueue_rebuild!(only = [])
      total = select(only).size
      write_status({ state: "queued", queued_at: Time.now.utc.iso8601, total: total, done: 0, problems: [] })
      SearchReindexJob.perform_later(Array(only).map(&:to_s))
      total
    end

    # dr:verify's verdict from a recorded rebuild, or nil when there is no recent one (the caller
    # then counts every index itself). A rebuild still queued or running is reported, not
    # waited for (decision 2026-11-08: "enqueue and move on").
    def grade_rebuild(status, now: Time.now.utc)
      return nil unless status.is_a?(Hash) && status[:queued_at]

      queued = Time.parse(status[:queued_at].to_s).utc
      return nil if now - queued > STATUS_FRESH_SECONDS

      progress = "#{status[:done]} of #{status[:total]} indexes done"
      case status[:state]
      when "queued"
        Grade.new(:ok, "search rebuild queued in the background at #{queued.strftime('%H:%M')} UTC (#{progress}) — results fill in as it runs")
      when "running"
        Grade.new(:ok, "search rebuilding in the background since #{queued.strftime('%H:%M')} UTC — #{progress}; results fill in as it runs")
      else
        problems = Array(status[:problems])
        return Grade.new(:ok, "rebuilt in the background: #{status[:total]}/#{status[:total]} indexes hold their records") if problems.empty?

        Grade.new(:warn, "rebuilt in the background with #{problems.size} of #{status[:total]} incomplete — #{problems.join('; ')}. " \
                         "Re-run: ONLY=<Index> bundle exec cap <stage> recovery:reindex_search")
      end
    rescue ArgumentError
      nil
    end

    # The run-level verdict for a set of index grades. Search problems WARN and never fail the
    # recovery (decision 2026-11-08): the restored database is complete, and an incomplete index
    # only means some search results are missing until it is rebuilt - the report lists which.
    # Search being UNREACHABLE still fails the run, through dr:verify's elastic_check.
    def verdict(grades)
      problems = grades.reject { |grade| grade.status == :ok }
      return Grade.new(:ok, "#{grades.size}/#{grades.size} indexes hold their records") if problems.empty?

      Grade.new(:warn, "#{problems.size} of #{grades.size} incomplete — #{problems.map(&:detail).join('; ')}. " \
                       "Re-run: ONLY=<Index> bundle exec cap <stage> recovery:reindex_search")
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
