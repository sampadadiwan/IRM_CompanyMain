# frozen_string_literal: true

# One-off data fix: backfill blank Investor#primary_email (and the associated
# investor_entity Entity#primary_email) for the stakeholders of a given entity_id,
# from an xlsx sheet (columns: Name, Category, Primary Email).
#
# An email from the sheet is applied ONLY if it is not already in use by any
# OTHER investor/entity on the platform (i.e. any entity_id, not just the target's) -
# both Investor.primary_email and Entity.primary_email are checked, since
# Investor#update_name matches/creates investor_entity by primary_email and a
# collision there would silently merge two unrelated stakeholders together.
#
# Matching sheet rows to Investor records is by investor_name, scoped to the
# target entity_id, case-insensitive/whitespace-normalized. Only investors
# whose primary_email is currently blank are touched; existing values are never
# overwritten. Same for investor_entity.primary_email.
#
# Writes via update_column(s) so no model callbacks/validations fire (per request) - the
# email-format check and the sync of primary_email_domain (see Investor#sync_primary_email_domain)
# that those would normally provide are replicated by hand below instead.
#
# Defaults to a dry run (no writes) - pass APPLY=true to actually persist.
#
# Usage:
#   bin/rails runner script/update_investor_primary_emails.rb TARGET_ENTITY_ID [xlsx_path]
#   APPLY=true bin/rails runner script/update_investor_primary_emails.rb TARGET_ENTITY_ID [xlsx_path]
#
# Example:
#   bin/rails runner script/update_investor_primary_emails.rb 123
#   APPLY=true bin/rails runner script/update_investor_primary_emails.rb 123 ~/Downloads/investors.xlsx

require "roo"

target_entity_id = ARGV[0]
xlsx_path = File.expand_path(ARGV[1] || "~/Downloads/investors.xlsx")
apply = ActiveModel::Type::Boolean.new.cast(ENV["APPLY"])

if target_entity_id.blank?
  puts "Usage: bin/rails runner script/update_investor_primary_emails.rb TARGET_ENTITY_ID [xlsx_path]"
  exit 1
end

unless File.exist?(xlsx_path)
  puts "Error: xlsx file not found at #{xlsx_path}"
  exit 1
end

target_entity = Entity.find(target_entity_id)

puts "========================================================================"
puts " UPDATE INVESTOR PRIMARY EMAILS  (#{apply ? "APPLY" : "DRY RUN - pass APPLY=true to persist"})"
puts "========================================================================"
puts "Entity: #{target_entity.name} (ID: #{target_entity.id})"
puts "Sheet:  #{xlsx_path}"
puts "------------------------------------------------------------------------"

def normalize_name(name)
  name.to_s.strip.squeeze(" ")
end

def normalize_email(raw)
  # A couple of rows in the source sheet have a stray trailing comma
  # (e.g. "kalsunil@gmail.com,") - take the first comma-separated token.
  raw.to_s.split(",").map(&:strip).reject(&:blank?).first.to_s.downcase
end

rows = Roo::Excelx.new(xlsx_path).sheet(0).parse(headers: true).drop(1)

updated = []
skipped = []

rows.each do |row|
  sheet_name = row["Name"]
  new_email = normalize_email(row["Primary Email"])

  if sheet_name.blank? || new_email.blank?
    skipped << { name: sheet_name, reason: "blank name/email in sheet row" }
    next
  end

  unless new_email.match?(URI::MailTo::EMAIL_REGEXP)
    # update_columns below bypasses Investor's own validates_format_of, so check it here instead.
    skipped << { name: sheet_name, reason: "#{new_email.inspect} is not a valid email format" }
    next
  end

  matches = Investor.where(entity_id: target_entity.id)
                     .where("LOWER(TRIM(investor_name)) = ?", normalize_name(sheet_name).downcase)
                     .to_a

  if matches.empty?
    skipped << { name: sheet_name, reason: "no matching investor found for entity##{target_entity.id}" }
    next
  elsif matches.size > 1
    skipped << { name: sheet_name, reason: "#{matches.size} investors matched this name - ambiguous, skipped" }
    next
  end

  investor = matches.first

  unless investor.primary_email.blank?
    skipped << { name: sheet_name, reason: "investor.primary_email already set (#{investor.primary_email}) - not overwriting" }
    next
  end

  # Platform-wide collision check (any entity_id) - Investor.primary_email. Fetched (not just
  # .exists?) so the skip reason can name who already owns the address.
  owning_investor = Investor.where.not(id: investor.id)
                             .where("LOWER(primary_email) = ?", new_email)
                             .includes(:entity)
                             .first
  if owning_investor
    skipped << { name: sheet_name, reason: "email #{new_email} already used by investor##{owning_investor.id} " \
                                            "#{owning_investor.investor_name.inspect} " \
                                            "(entity_id: #{owning_investor.entity_id}, entity: #{owning_investor.entity&.name.inspect})" }
    next
  end

  # Platform-wide collision check - Entity.primary_email (identity-matching key,
  # see Investor#update_name / find_or_build_investor_entity).
  owning_entity = Entity.where.not(id: investor.investor_entity_id)
                         .where("LOWER(primary_email) = ?", new_email)
                         .first
  if owning_entity
    skipped << { name: sheet_name, reason: "email #{new_email} already used by entity##{owning_entity.id} " \
                                            "#{owning_entity.name.inspect} (entity_type: #{owning_entity.entity_type})" }
    next
  end

  investor_entity = investor.investor_entity
  entity_email_blank = investor_entity.primary_email.blank?

  puts "#{apply ? "Updating" : "Would update"}: investor##{investor.id} #{investor.investor_name.inspect} " \
       "+ entity##{investor_entity.id} -> #{new_email}" \
       "#{" (entity already has an email set - leaving it alone)" unless entity_email_blank}"

  if apply
    ActiveRecord::Base.transaction do
      # update_column(s): skip validations/callbacks. Investor#sync_primary_email_domain
      # (a before_save) normally keeps primary_email_domain in step with primary_email for
      # InvestorEmailMatcher's indexed lookup - replicate that by hand so it isn't silently
      # left stale.
      investor.update_columns(primary_email: new_email, primary_email_domain: new_email.split("@").last.presence&.downcase)
      investor_entity.update_column(:primary_email, new_email) if entity_email_blank
    end
  end

  updated << { name: sheet_name, email: new_email, investor_id: investor.id, entity_id: investor_entity.id }
rescue => e
  skipped << { name: sheet_name, reason: "error: #{e.class} #{e.message}" }
end

puts "------------------------------------------------------------------------"
puts "Updated: #{updated.size}"
puts "Skipped: #{skipped.size}"
puts

if skipped.any?
  puts "Skipped detail:"
  skipped.each { |s| puts "  - #{s[:name]}: #{s[:reason]}" }
end

puts "========================================================================"
puts apply ? "Done." : "Dry run complete - no changes were made. Re-run with APPLY=true to persist."
puts "========================================================================"
