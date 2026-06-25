# frozen_string_literal: true

# Rerun allocations for the latest AllocationRun of each fund for given entities.
#
# For each entity, finds all funds, then for each fund finds the latest
# AllocationRun and reruns the allocation using that run's parameters.
# Runs sequentially so logs are readable. Errors on one fund don't stop others.
#
# Usage:
#   rails runner scripts/rerun_allocations.rb <entity_id_1> [entity_id_2 ...]
#
# Example:
#   rails runner scripts/rerun_allocations.rb 1 2 3

require "timeout"

# Timeout per allocation job (default 30 min, override via ALLOCATION_TIMEOUT env var)
ALLOCATION_TIMEOUT = (ENV["ALLOCATION_TIMEOUT"] || 1800).to_i

entity_ids = ARGV.map(&:to_i)

if entity_ids.empty?
  puts "Usage: rails runner scripts/rerun_allocations.rb <entity_id_1> [entity_id_2 ...]"
  exit 1
end

# ------------------------------------------------------------------
# Resolve funds and their latest AllocationRun for each entity
# ------------------------------------------------------------------
jobs = []

entity_ids.each do |entity_id|
  entity = Entity.find_by(id: entity_id)

  if entity.nil?
    puts "⚠️  Entity #{entity_id} not found, skipping"
    next
  end

  puts "Processing entity #{entity_id} (#{entity.short_name || entity.name})..."

  funds = entity.funds.to_a

  if funds.empty?
    puts "  ⚠️  No funds found for entity #{entity_id}, skipping"
    next
  end

  funds.each do |fund|
    last_run = AllocationRun.where(fund_id: fund.id).order(created_at: :desc).first

    if last_run.nil?
      puts "  ⚠️  No AllocationRun found for Fund #{fund.id} (#{fund.name}). Skipping."
      next
    end

    jobs << {
      fund_id:           fund.id,
      label:             fund.name,
      start_date:        last_run.start_date,
      end_date:          last_run.end_date,
      allocation_run_id: last_run.id,
      user_id:           last_run.user_id,
      run_allocations:   last_run.run_allocations,
      explain:           true,
      generate_soa:      last_run.generate_soa,
      statement_for:     last_run.statement_for,
      template_id:       last_run.template_name,
      fund_ratios:       last_run.fund_ratios,
      rule_for:          last_run.rule_for,
      tag_list:          last_run.tag_list,
    }

    puts "  ✓ Fund #{fund.id} (#{fund.name}): allocation_run_id=#{last_run.id}, " \
         "#{last_run.start_date} → #{last_run.end_date}"
  end
end

if jobs.empty?
  puts
  puts "No eligible funds found. Exiting."
  exit 0
end

puts
puts "=" * 60
puts "Starting #{jobs.size} allocation(s) sequentially..."
puts "=" * 60

# ------------------------------------------------------------------
# Run all jobs sequentially
# ------------------------------------------------------------------
success_count = 0
error_count   = 0

jobs.each do |j|
  puts
  puts "▶️  [#{j[:fund_id]}] #{j[:label]} — " \
       "#{j[:start_date]} → #{j[:end_date]}, allocation_run_id=#{j[:allocation_run_id]}"
  $stdout.flush

  # Run the job in a thread so we can show a heartbeat while it works
  result = nil
  job_thread = Thread.new do
    begin
      Timeout.timeout(ALLOCATION_TIMEOUT) do
        AccountEntryAllocationJob.perform_now(
          j[:fund_id],
          j[:start_date],
          j[:end_date],
          user_id:           j[:user_id],
          run_allocations:   j[:run_allocations],
          explain:           j[:explain],
          generate_soa:      j[:generate_soa],
          statement_for:     j[:statement_for],
          template_id:       j[:template_id],
          fund_ratios:       j[:fund_ratios],
          rule_for:          j[:rule_for],
          tag_list:          j[:tag_list],
          allocation_run_id: j[:allocation_run_id],
        )
      end
      result = :success
    rescue Timeout::Error
      result = :timeout
    rescue => e
      result = { error: e }
    end
  end

  # Heartbeat while job is running
  dots = 0
  while job_thread.alive?
    sleep 5
    dots += 1
    print "." * dots + "\r"
    $stdout.flush
  end

  job_thread.join
  print " " * dots + "\r"  # clear heartbeat dots
  $stdout.flush

  case result
  when :success
    puts "✅ [#{j[:fund_id]}] #{j[:label]} — completed"
    success_count += 1
  when :timeout
    puts "⏰ [#{j[:fund_id]}] #{j[:label]}: timed out after #{ALLOCATION_TIMEOUT}s"
    error_count += 1
  when Hash
    e = result[:error]
    puts "❌ [#{j[:fund_id]}] #{j[:label]}: #{e.class} — #{e.message}"
    puts e.backtrace.first(5).map { |l| "   #{l}" }.join("\n")
    error_count += 1
  end
end

puts
puts "=" * 60
puts "Finished. #{success_count} succeeded, #{error_count} failed."
