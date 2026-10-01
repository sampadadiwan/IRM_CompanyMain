# frozen_string_literal: true

# One-off housekeeping for users.regions.
#
# `regions` is a free-text string edited through the Administrate user dashboard, and written
# in a different shape by the multi-region user sync, so production holds all of:
#
#   "IN,US"            the intended form
#   " in ,US, us"      hand-typed, with spacing, casing and a duplicate
#   '["US","IN"]'      the JSON array the sync writes
#
# Everything that READS the column now normalises it (User#switchable_region_codes), so this is
# a safety net rather than the mechanism - but leaving the stored values inconsistent means the
# next person to look at the column, or query it, sees three shapes.
#
# Run per region. IN and US are independent deployments with independent databases; there is no
# "run it once for both".
#
#   bundle exec rake users:normalize_regions              # report only, writes nothing
#   EXECUTE=1 bundle exec rake users:normalize_regions    # apply
namespace :users do
  desc "Normalise users.regions (trim, upcase, dedupe, sort). Dry run unless EXECUTE=1."
  task normalize_regions: :environment do
    execute = ENV["EXECUTE"] == "1"
    changed = 0
    scanned = 0

    puts(execute ? "Applying changes." : "DRY RUN - nothing will be written. Re-run with EXECUTE=1 to apply.")

    # in_batches, selecting only the two columns we touch: users is not one of the huge tables
    # but there is no reason to pull every column into memory for a string rewrite.
    User.where.not(regions: [nil, ""]).select(:id, :regions).in_batches(of: 1_000) do |batch|
      batch.each do |user|
        scanned += 1
        current = user.regions
        # Reuses the parser that already understands all three stored shapes.
        normalized = user.normalize_regions_array(current).join(",")
        next if normalized == current

        changed += 1
        puts format("  user %-8s %-28s -> %s", user.id, current.inspect, normalized.inspect)
        # update_column: this is a data tidy-up, not a user action - no validations, no
        # callbacks, no touching updated_at, and nothing that would re-trigger a region sync.
        user.update_column(:regions, normalized) if execute
      end
    end

    puts format("Scanned %d users; %d %s.", scanned, changed, execute ? "updated" : "would change")
    # A region is never added to or removed from anyone: normalize_regions_array only trims,
    # upcases, de-duplicates and sorts what is already there.
    puts "No region was added to or removed from any user." if changed.positive?
  end
end
