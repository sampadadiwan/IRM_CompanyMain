# frozen_string_literal: true

# Run 3 AccountEntryAllocationJobs in parallel for different funds.
#
# Usage:
#   rails runner scripts/run_parallel_allocations.rb
#
# Each fund uses its last AllocationRun (most recent by created_at).

funds = [
  { fund_id: 319, start_date: Date.parse("Sat, 28 Mar 2026"), end_date: Date.parse("Tue, 31 Mar 2026"), label: "Master Fund"   },
  { fund_id: 320, start_date: Date.parse("Sat, 14 Mar 2026"), end_date: Date.parse("Tue, 31 Mar 2026"), label: "Feeder Fund"    },
  { fund_id: 321, start_date: Date.parse("Tue, 17 Mar 2026"), end_date: Date.parse("Tue, 31 Mar 2026"), label: "Feeder Fund"    },
]

# Shared parameters (from the proven invocation)
shared_params = {
  rule_for:          "",
  tag_list:          nil,
  run_allocations:   true,
  explain:           true,
  user_id:           484,
  generate_soa:      false,
  statement_for:     "Commitment",
  template_id:       "51859",
  fund_ratios:       false,
  sample:            false,
}

# ------------------------------------------------------------------
# Resolve the last allocation_run_id for each fund
# ------------------------------------------------------------------
funds.each do |f|
  last_run = AllocationRun.where(fund_id: f[:fund_id]).order(created_at: :desc).first

  if last_run.nil?
    puts "⚠️  WARNING: No AllocationRun found for Fund #{f[:fund_id]} (#{f[:label]}). Skipping."
    f[:skip] = true
  else
    f[:allocation_run_id] = last_run.id
    puts "✓ Fund #{f[:fund_id]} (#{f[:label]}): allocation_run_id = #{last_run.id} (created #{last_run.created_at})"
  end
end

puts

# ------------------------------------------------------------------
# Run eligible jobs in parallel
# ------------------------------------------------------------------
threads = funds.select { |f| !f[:skip] }.map do |f|
  Thread.new do
    begin
      puts "▶️  Starting allocation for Fund #{f[:fund_id]} (#{f[:label]}) — " \
           "#{f[:start_date]} → #{f[:end_date]}, allocation_run_id=#{f[:allocation_run_id]}"

      AccountEntryAllocationJob.perform_now(
        f[:fund_id],
        f[:start_date],
        f[:end_date],
        **shared_params,
        allocation_run_id: f[:allocation_run_id],
      )

      puts "✅ Completed allocation for Fund #{f[:fund_id]} (#{f[:label]})"
    rescue => e
      puts "❌ ERROR for Fund #{f[:fund_id]} (#{f[:label]}): #{e.class} — #{e.message}"
      puts e.backtrace.first(5).map { |l| "   #{l}" }.join("\n")
    end
  end
end

# Wait for all threads to finish
threads.each(&:join)

puts
puts "🎯 All allocation jobs finished."
