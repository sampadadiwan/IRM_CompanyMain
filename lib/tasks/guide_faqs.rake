# frozen_string_literal: true

# Managed user-guide FAQs (docs/modules/ai/customer_support_agent/guide_faq_search_prd.md).
#
#   rake guide_faqs:import_markdown [REFRESH=1] # FAQ sections in docs/user_guides → FaqEntry
#   rake guide_faqs:export FILE=tmp/faqs.xlsx # spreadsheet of every FAQ (default tmp/faqs.xlsx)
#   rake guide_faqs:import FILE=tmp/faqs.xlsx # load a spreadsheet (creates/updates, never deletes)
#   rake guide_faqs:verify                    # run FaqVerificationJob now
#   rake guide_search:reindex                 # rebuild the Elasticsearch FAQ index
#   rake guide_search:eval                    # how often each FAQ's own question finds it
namespace :guide_faqs do
  desc "Import the FAQ sections in docs/user_guides/**/*.md as published FAQ entries " \
       "(REFRESH=1 also updates entries never edited in FAQ Manager and archives removed questions)"
  task import_markdown: :environment do
    result = FaqMarkdownImporter.new.call(refresh: ENV["REFRESH"].present?)
    puts "Created #{result.created}, updated #{result.updated}, archived #{result.archived}, " \
         "skipped #{result.skipped}, #{result.errors.size} errors"
    result.errors.each { |e| puts "  #{e}" }
  end

  desc "Export all FAQ entries to a spreadsheet (FILE=tmp/faqs.xlsx)"
  task export: :environment do
    path = ENV.fetch("FILE", Rails.root.join("tmp/faqs.xlsx").to_s)
    File.binwrite(path, FaqSpreadsheet.export(FaqEntry.all))
    puts "Wrote #{FaqEntry.count} FAQs to #{path}"
  end

  desc "Import FAQ entries from a spreadsheet (FILE=path.xlsx, optional USER_EMAIL recorded as editor)"
  task import: :environment do
    path = ENV.fetch("FILE") { abort "FILE=path/to/faqs.xlsx is required" }
    email = ENV.fetch("USER_EMAIL", nil).presence
    user = email && User.find_by!(email: email)
    result = FaqSpreadsheet.import(path, user: user)
    puts result.summary
    result.errors.each { |e| puts "  #{e}" }
  end

  desc "Flag published FAQs with broken paths or links, or overdue for re-verification"
  task verify: :environment do
    FaqVerificationJob.perform_now
    puts "#{FaqEntry.published.where(needs_verification: true).count} published FAQs need verification"
  end
end

namespace :guide_search do
  desc "Rebuild the Elasticsearch FAQ index"
  task reindex: :environment do
    FaqEntryIndex.reset!
    puts "Indexed #{FaqEntryIndex.count} published FAQs"
  end

  desc "Search each published FAQ's own question and report how often it ranks first or in the top 3 (LIMIT=n)"
  task eval: :environment do
    entries = FaqEntry.published.order("RAND()").limit(ENV.fetch("LIMIT", 300).to_i)
    entries = FaqEntry.published.limit(ENV.fetch("LIMIT", 300).to_i) unless ActiveRecord::Base.connection.adapter_name.match?(/mysql/i)
    ranks = entries.map do |entry|
      result = GuideSearch.new.call(entry.question)
      [entry, result.hits.index { |hit| hit.entry_id == entry.id }, result.backend]
    end
    total = ranks.size.nonzero? || 1
    puts "Backend: #{ranks.map(&:last).tally}"
    puts format("recall@1 %.1f%%  recall@3 %.1f%%  (%d questions)",
                100.0 * ranks.count { |_, r, _| r&.zero? } / total, 100.0 * ranks.count { |_, r, _| r && r < 3 } / total, ranks.size)
    ranks.reject { |_, r, _| r && r < 3 }.first(20).each { |e, r, _| puts "  miss (rank #{r || '-'}): #{e.guide_key}: #{e.question}" }
  end
end
