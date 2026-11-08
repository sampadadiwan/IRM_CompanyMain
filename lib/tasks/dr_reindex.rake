# frozen_string_literal: true

# Rebuilds the Elasticsearch indexes after a disaster recovery (openspec
# fix-dr-search-index-after-restore). Elasticsearch is not backed up, so a recovered environment
# starts with empty indexes and every search box returns nothing. An incomplete index is a
# WARNING, never a failure (decision 2026-11-08): the data is complete, only some search results
# are missing until it is re-run.
#
# Two ways in, sharing Dr::SearchIndexes.rebuild!:
# - dr:reindex_search_later - what aws:setup_infra runs: queues SearchReindexJob and returns at
#   once ("enqueue and move on", decision 2026-11-08). The job runs when Sidekiq starts.
# - dr:reindex_search - blocking, for an operator re-running one index (ONLY=FolderIndex).
#
# Why not `rake chewy:reset`: it finds indexes via Chewy's indices_path (app/chewy), and this app
# keeps them in app/packs/**/models, so it resets none - and it ignores import errors anyway.
namespace :dr do
  desc "DR: queue the search rebuild as a background job (SearchReindexJob) and return at once"
  task reindex_search_later: :environment do
    total = Dr::SearchIndexes.enqueue_rebuild!(ENV["ONLY"].to_s.split(","))
    puts "🔎 Search rebuild queued in the background: #{total} indexes (SearchReindexJob, chewy queue). " \
         "It runs when Sidekiq starts; dr:verify and the DR report show its progress."
    Dr::SearchIndexes.excluded.each do |index|
      puts "   ⏭  #{index.name} skipped — #{Dr::SearchIndexes::EXCLUDED[index.name]}"
    end
  rescue ArgumentError => e
    abort "❌ #{e.message}"
  end

  desc "DR: rebuild search indexes now, blocking (ONLY=FolderIndex,... for some); warns, never fails"
  task reindex_search: :environment do
    indexes = Dr::SearchIndexes.select(ENV["ONLY"].to_s.split(","))
    puts "🔎 Rebuilding #{indexes.size} search indexes from MySQL"
    Dr::SearchIndexes.excluded.each do |index|
      puts "   ⏭  #{index.name} skipped — #{Dr::SearchIndexes::EXCLUDED[index.name]}"
    end

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    # Exact counts only when the site is in maintenance (MAINTENANCE=true); otherwise users may be
    # writing while it runs, so allow the small verification tolerance
    rows = Dr::SearchIndexes.rebuild!(indexes, exact: ENV["MAINTENANCE"] == "true", on_progress: lambda { |_, (_, grade, seconds)|
      puts "   #{grade.status == :ok ? '✅' : '⚠️ '} #{grade.detail} (#{seconds}s)"
    })

    # Summary: the slowest indexes first, so a long run is explained at a glance
    total = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(1)
    slowest = rows.max_by(3) { |_, _, seconds| seconds }.map { |name, _, seconds| "#{name} #{seconds}s" }
    verdict = Dr::SearchIndexes.verdict(rows.map { |_, grade, _| grade })
    puts "\n#{verdict.status == :ok ? '🟢' : '🟡'} Search reindex — #{verdict.detail} in #{total}s (slowest: #{slowest.join(', ')})"
  rescue ArgumentError => e
    abort "❌ #{e.message}"
  end
end
