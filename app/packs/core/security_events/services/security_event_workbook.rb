# frozen_string_literal: true

# Builds the security events spreadsheet (OWASP review 2026-11 M11): the Download from the screen (one sheet, H31)
# and the Monday pack (five sheets, H34). One builder, so both spell rows the same way and both escape the same way.
#
# E44 — a cell that starts with = + - @ (or a tab / carriage return) is prefixed with ' so a spreadsheet program
# shows it as text and never runs it as a formula. A user agent or a key name is typed by someone else.
class SecurityEventWorkbook
  HEADERS = ["When", "Firm", "Group", "Event", "Details", "Outcome", "Account", "Done by", "On behalf of", "Door",
             "IP", "Browser", "Region", "Request id"].freeze
  FORMULA_START = /\A[=+\-@\t\r]/
  # Rows read per batch, each batch with its people and firms preloaded
  BATCH = 1000

  def initialize
    @package = Axlsx::Package.new
    @package.use_shared_strings = true
  end

  # One sheet of events, newest first
  # @param name [String] the sheet name
  # @param scope [ActiveRecord::Relation] SecurityEvent rows (already policy-scoped and filtered)
  def add_events(name, scope)
    @package.workbook.add_worksheet(name: name.first(31)) do |sheet|
      sheet.add_row HEADERS
      # Keyset batches with the people preloaded per batch — never one query per row
      scope.unscope(:order).includes(:entity, :user, :actor, :impersonator).find_each(batch_size: BATCH, order: :desc) do |event|
        sheet.add_row row_for(event), types: Array.new(HEADERS.size, :string)
      end
    end
    self
  end

  # H34 — "Failed sign-ins by account": per account (or per digest, for an address with no account) per day
  # @param scope [ActiveRecord::Relation] the week's rows
  def add_failed_sign_ins_by_account(scope)
    counts = Hash.new(0)
    # Only the columns needed; the week's failures are a few hundred rows
    scope.where(kind: "sign_in.failed").includes(:user, :entity)
         .find_each(batch_size: BATCH) do |event|
      key = [event.entity&.name || "CapHive only", account_label(event), event.occurred_at.in_time_zone.to_date]
      counts[key] += 1
    end
    @package.workbook.add_worksheet(name: "Failed sign-ins by account") do |sheet|
      sheet.add_row ["Firm", "Account", "Day", "Failed sign-ins"]
      counts.sort_by { |(firm, account, day), _| [day, firm, account] }.each do |(firm, account, day), count|
        sheet.add_row [safe(firm), safe(account), I18n.l(day, locale: :en), count], types: %i[string string string integer]
      end
    end
    self
  end

  # @return [String] the xlsx bytes
  def to_stream
    @package.to_stream.read
  end

  private

  def row_for(event)
    [I18n.l(event.occurred_at.in_time_zone, locale: :en), event.entity&.name || "CapHive only", event.category_label,
     event.label, event.details_text, event.failure? ? "Failed" : "Succeeded", account_label(event),
     event.actor&.full_name || "System", event.impersonator&.full_name, event.door_label, event.ip_address,
     event.user_agent, event.region, event.request_id].map { |value| safe(value) }
  end

  # The account's name and email; for an unknown address only the start of its fingerprint
  def account_label(event)
    return "#{event.user.full_name} <#{event.user.email}>" if event.user
    return "Unknown email (fingerprint #{event.identifier_digest.first(12)})" if event.identifier_digest

    ""
  end

  # E44 — text a spreadsheet would run as a formula is kept as text
  def safe(value)
    text = value.to_s
    text.match?(FORMULA_START) ? "'#{text}" : text
  end
end
