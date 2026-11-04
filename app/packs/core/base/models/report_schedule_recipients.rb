# The recipients typed into a Report Builder schedule: split, tidied and
# checked. Used twice — by the Delivery tab's check before the popup and by the
# save itself — so the popup and the server can never disagree.
#
#   "Meera@Acme.test; ravi@acme.test\nmeera@acme.test, lp@gmail.com, bob@"
#     emails    → ["meera@acme.test", "ravi@acme.test", "lp@gmail.com", "bob@"]
#     invalid   → ["bob@"]
#     outsiders → ["lp@gmail.com"]          (no Acme user has that email)
#     error     → "bob@ isn't an email address"
#
# "Outside" is relative to the report's company — the one a scheduled run reads
# and sends from (fix-tenant-isolation R4).
# Worked examples H4, H5, E4, X2, X3, X4 — openspec/changes/report-builder-delivery/business-rules.md
class ReportScheduleRecipients
  SEPARATORS = /[\s,;]+/

  def initialize(text, entity:)
    @text   = text
    @entity = entity
  end

  # Lower-case, without duplicates, in the order typed (E4)
  def emails
    @emails ||= Array(@text).join(",").split(SEPARATORS).map { |e| e.strip.downcase }.compact_blank.uniq
  end

  # Anything that doesn't look like name@domain.tld (X2)
  def invalid
    @invalid ||= emails.reject { |e| e.match?(URI::MailTo::EMAIL_REGEXP) && e.split("@").last.include?(".") }
  end

  # Valid addresses no user of the company has (H5, X4)
  def outsiders
    @outsiders ||= begin
      valid = emails - invalid
      inside = valid.any? ? User.where(entity_id: @entity.id).where("LOWER(email) IN (?)", valid).pluck(:email).map(&:downcase) : []
      valid - inside
    end
  end

  # nil when the list can be saved, else what to fix (X2, X3)
  def error
    return "Add at least one email" if emails.empty?
    return nil if invalid.empty?

    invalid.one? ? "#{invalid.first} isn't an email address" : "#{invalid.to_sentence} aren't email addresses"
  end
end
