# frozen_string_literal: true

# Rebuilds the Elasticsearch indexes after a disaster recovery, and fails unless every one comes
# back complete (openspec fix-dr-search-index-after-restore).
#
# Why it exists: Elasticsearch is not backed up, so a recovered environment starts with empty
# indexes and every search box returns nothing. `rake chewy:reset` cannot fix that here - it finds
# indexes via Chewy's indices_path (app/chewy), and this app keeps them in app/packs/**/models, so
# it resets none - and it ignores import errors anyway.
#
# Runs on an app server via `cap <stage> recovery:reindex_search`. aws:setup_infra calls it as its
# own phase, AFTER the database restore and BEFORE traffic is switched back on - nothing writes
# while it runs, so each index's count must match its MySQL scope exactly.
namespace :dr do
  desc "DR: rebuild every search index the live app maintains; fail on any import error or count mismatch"
  task reindex_search: :environment do
    indexes = Dr::SearchIndexes.indexes
    # ONLY=FolderIndex,FundIndex re-runs just the named indexes (e.g. the one that failed)
    only = ENV["ONLY"].to_s.split(",").map(&:strip).reject(&:empty?)
    if only.any?
      unknown = only - indexes.map(&:name)
      abort "❌ Not a DR search index: #{unknown.join(', ')} (known: #{indexes.map(&:name).join(', ')})" if unknown.any?
      indexes = indexes.select { |index| only.include?(index.name) }
    end
    puts "🔎 Rebuilding #{indexes.size} search indexes from MySQL (traffic is off; counts must match exactly)"
    Dr::SearchIndexes.excluded.each do |index|
      puts "   ⏭  #{index.name} skipped — #{Dr::SearchIndexes::EXCLUDED[index.name]}"
    end

    started_all = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rows = indexes.map do |index|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        # reset! builds a fresh suffixed index, imports into it, then swaps the alias - readers never
        # see a half-built index. It returns false (does not raise) when documents fail to import.
        imported = index.reset!((Time.now.to_f * 1000).round, apply_journal: false)
        grade = Dr::SearchIndexes.grade(index_name: index.name, es: Dr::SearchIndexes.es_count(index),
                                        db: Dr::SearchIndexes.db_count(index), imported: imported, exact: true)
      rescue StandardError => e
        # Keep going: one run should show every index that needs fixing, not just the first
        grade = Dr::SearchIndexes::Grade.new(:fail, "#{index.name}: #{e.class}: #{e.message.lines.first&.strip}")
      end
      seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
      puts "   #{grade.status == :ok ? '✅' : '❌'} #{grade.detail} (#{seconds}s)"
      [index.name, grade, seconds]
    end

    # Summary: the slowest indexes first, so a long DR phase is explained at a glance
    total = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_all).round(1)
    failed = rows.reject { |_, grade, _| grade.status == :ok }
    slowest = rows.max_by(3) { |_, _, seconds| seconds }.map { |name, _, seconds| "#{name} #{seconds}s" }
    puts "\n#{failed.empty? ? '🟢' : '🔴'} Search reindex — #{rows.size - failed.size}/#{rows.size} indexes complete in #{total}s " \
         "(slowest: #{slowest.join(', ')})"
    next if failed.empty?

    failed.each { |_, grade, _| puts "   ❌ #{grade.detail}" }
    abort "❌ Search reindex FAILED for #{failed.size} index(es) — search would be incomplete; fix and re-run " \
          "`bundle exec cap <stage> recovery:reindex_search`"
  end
end
