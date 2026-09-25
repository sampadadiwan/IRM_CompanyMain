# Drift guard for the email attachment size limit.
#
# The limit is enforced in ONE place — ApplicationMailer#attachment_allowed?, called by
# attach_doc and pw_protect_attach_file, which are the only two methods that attach a
# Document row. That design only holds while no mailer assigns `attachments[...]` directly,
# and nothing stops a future one from doing so. These steps make that invariant executable,
# in the same spirit as features/ai/mcp_server/mcp_ontology.feature.
#
# Added after a 20.3 MB PDF reached 137 investors at ~28 MB per message and roughly nine in
# ten deliveries bounced, while the app recorded every one as "Sent". See
# docs/operations/troubleshooting/24092026_peercapital_annual_report_email_bounces.md

# Every known `attachments[...] =` site in app/, by file, with the number expected in each.
# Keyed by file rather than line so ordinary edits don't break it, while a NEW attachment
# site anywhere still fails the scenario.
EXPECTED_ATTACHMENT_SITES = {
  # GUARDED — attach_doc and pw_protect_attach_file, both of which call attachment_allowed?
  # before touching the file. Every notification mailer attaches through these two.
  "app/packs/core/base/mailers/application_mailer.rb" => 2,

  # KNOWN EXEMPT — these attach generated output (an XLSX export, a scheduled report file)
  # rather than a Document row, build the bytes in memory, and call mail() directly instead
  # of going through send_mail, so there is no Noticed::Notification to record a skip
  # against. They are also single-recipient, user-initiated downloads, so an oversized one
  # bounces a single email back to the person who asked for it rather than fanning out to
  # an investor list. Guarding them needs a different mechanism and is tracked separately.
  "app/packs/core/base/mailers/report_mailer.rb" => 1,   # scheduled_report
  "app/packs/core/users/mailers/user_mailer.rb" => 2     # audit_download, model_download
}.freeze

# Matches an assignment only — a line that merely mentions attachments[...] in a comment
# or reads from it is not an attachment site.
ATTACHMENT_ASSIGNMENT = /^\s*attachments\[[^\]]*\]\s*=[^=]/

def attachment_sites_in_app
  Rails.root.glob("app/**/*.rb").each_with_object(Hash.new(0)) do |path, counts|
    relative = Pathname.new(path).relative_path_from(Rails.root).to_s
    File.foreach(path) { |line| counts[relative] += 1 if line.match?(ATTACHMENT_ASSIGNMENT) }
  end.reject { |_, count| count.zero? }
end

# Reads a method body out of a source file by name, from `def <name>` to the matching `end`
# at the same indentation. Good enough for the flat, two-space-indented mailer methods here.
def method_source(path, method_name)
  lines = File.readlines(path)
  # `self.` so class methods are found too — DocumentSender.send is `def self.send`.
  # The trailing lookahead rather than \b: for a predicate like `blocked_by_attachment_size?`
  # the next character is `(`, and \b never matches between two non-word characters, so \b
  # would silently fail to find every ?/!-suffixed method.
  start = lines.index { |l| l.match?(/^(\s*)def (self\.)?#{Regexp.escape(method_name)}(?![\w?!])/) }
  return nil if start.nil?

  indent = lines[start][/^\s*/]
  finish = ((start + 1)...lines.length).find { |i| lines[i] == "#{indent}end\n" }
  return nil if finish.nil?

  lines[start..finish].join
end

Then('every mailer attachment site is size-guarded or a known exemption') do
  found = attachment_sites_in_app

  unexpected = found.reject { |file, _| EXPECTED_ATTACHMENT_SITES.key?(file) }
  expect(unexpected).to be_empty, <<~MSG
    New attachment site(s) found that the size limit does not cover: #{unexpected.keys.join(', ')}.

    Attach Documents via ApplicationMailer#attach_doc or #pw_protect_attach_file so
    attachment_allowed? applies (NotificationAttachmentPreflight::MAX_ATTACHMENT_BYTES). If this genuinely
    cannot go through those, add it to EXPECTED_ATTACHMENT_SITES in
    features/step_definitions/notification_attachment_size_steps.rb with a reason.
  MSG

  changed = EXPECTED_ATTACHMENT_SITES.reject { |file, count| found[file] == count }
  expect(changed).to be_empty, <<~MSG
    Attachment site count changed in: #{changed.keys.join(', ')}
    expected #{changed.map { |f, c| "#{f}=#{c}" }.join(', ')}, found #{changed.map { |f, _| "#{f}=#{found[f]}" }.join(', ')}.

    A new `attachments[...] =` was added to a file that already had one. Confirm it goes
    through attachment_allowed?, then update the count.
  MSG
end

# Every place that fans a notification out to many recipients, and the notification it sends.
# The send-time guard already makes an oversized email impossible on all of these; the
# preflight is what turns "every recipient skipped one by one, reported 5 minutes later" into
# "nothing enqueued, operator told immediately".
#
# Keyed by the METHOD that does the fanning out, not just the file. A file-level check passes
# as soon as the constant appears anywhere in it, which is how perform_by_investor_kyc sat
# unguarded in a file that already mentioned the preflight for the commitment path.
PREFLIGHT_CALL_SITES = {
  ["app/packs/core/documents/services/document_sender.rb", "send"] => "Send Document",
  ["app/packs/funds/capital_calls/jobs/capital_call_job.rb", "notify"] => "Capital call notices",
  ["app/packs/funds/capital_calls/models/capital_call.rb", "reminder_capital_call"] => "Capital call reminders",
  ["app/packs/funds/capital_distribution_payments/jobs/capital_distribution_payment_notification_job.rb", "perform"] => "Distribution notices",
  ["app/packs/funds/funds/jobs/fund_notification_job.rb", "perform_by_capital_commitment"] => "Adhoc fund notification",
  ["app/packs/funds/funds/jobs/fund_notification_job.rb", "perform_by_investor_kyc"] => "Adhoc KYC notification"
}.freeze

# True when the named method reaches the preflight — directly, or through one helper defined
# in the same file (CapitalCallJob#notify delegates to #blocked_by_attachment_size?). Raises
# rather than returning false when the method is gone, so a rename is reported as a rename
# instead of masquerading as a missing preflight.
def preflight_reachable?(path, method_name, depth = 1)
  source = method_source(path, method_name)
  raise "#{path} has no ##{method_name} — has it been renamed?" if source.nil? && depth.positive?
  return false if source.nil?
  return true if source.include?("NotificationAttachmentPreflight")
  return false if depth.zero?

  # Any bare identifier in the body that is itself a method in this file.
  source.scan(/\b([a-z_][a-z0-9_]*[?!]?)/).flatten.uniq.any? do |candidate|
    candidate != method_name && preflight_reachable?(path, candidate, depth - 1)
  end
end

Then('every bulk notification send runs the attachment preflight') do
  missing = PREFLIGHT_CALL_SITES.reject do |(path, method_name), _label|
    preflight_reachable?(Rails.root.join(path).to_s, method_name)
  end

  expect(missing).to be_empty, <<~MSG
    These bulk sends no longer call NotificationAttachmentPreflight:
    #{missing.map { |(path, method_name), label| "  #{label} - #{path}##{method_name}" }.join("\n")}

    Without it an oversized attachment is still never emailed (attachment_allowed? stops it
    at send time), but the operator only finds out from the skipped-notification report
    minutes later, after every recipient has been individually skipped.
  MSG
end

Then('the document attachment methods all enforce the size limit') do
  path = Rails.root.join("app/packs/core/base/mailers/application_mailer.rb").to_s

  %w[attach_doc pw_protect_attach_file].each do |method_name|
    source = method_source(path, method_name)
    expect(source).not_to be_nil, "ApplicationMailer##{method_name} not found — has it been renamed?"
    expect(source).to include("attachment_allowed?"),
                      "ApplicationMailer##{method_name} no longer calls attachment_allowed?, so it " \
                      "will attach a document of any size. This is the guard the whole limit rests on."
  end
end

# Exercises the shared limit through the preflight service rather than a mailer, so the
# boundary itself is pinned regardless of which notification is sending.
Then('the attachment size limit is enforced at the boundary') do
  limit = NotificationAttachmentPreflight::MAX_ATTACHMENT_BYTES
  expect(limit).to be_positive

  under = build_sized_document("Under", limit - 1)
  over  = build_sized_document("Over", limit + 1)

  expect(NotificationAttachmentPreflight.violations([under])).to be_empty
  expect(NotificationAttachmentPreflight.violations([over])).not_to be_empty

  # Two DISTINCTLY NAMED documents that each fit but together do not — the running-total half
  # of the rule. The names must differ: attachments[] is keyed by filename, so two documents
  # sharing a name become one MIME part and correctly do NOT breach the total.
  half_a = build_sized_document("Half A", (limit / 2) + 1)
  half_b = build_sized_document("Half B", (limit / 2) + 1)
  expect(NotificationAttachmentPreflight.violations([half_a])).to be_empty
  expect(NotificationAttachmentPreflight.violations([half_a, half_b])).not_to be_empty

  # Same document name twice is ONE attachment, not two — must not be refused.
  same_name = build_sized_document("Same", (limit / 2) + 1)
  expect(NotificationAttachmentPreflight.violations([same_name, same_name.dup])).to be_empty

  # A rejected document contributes nothing to the total, so a small one after a huge one
  # is still fine and is not named in the operator's email.
  huge  = build_sized_document("Huge", limit + 1)
  small = build_sized_document("Small", 1024)
  expect(NotificationAttachmentPreflight.violations([huge, small]).size).to eq(1)

  # A row with no file at all must not raise. uploaded_file_extension reads file.metadata and
  # blows up on nil, and this check runs on every accepted document — a read-only size check
  # must never be what takes a send down.
  expect { NotificationAttachmentPreflight.violations([Document.new(name: "No File")]) }.not_to raise_error
end

# In-memory only: never saved, and deliberately has no bytes in storage, so anything that
# reads the file instead of its metadata size will blow up rather than quietly pass.
def build_sized_document(name, bytes)
  doc = Document.new(name: name)
  doc.file_data = {
    "id" => "size-guard/#{name.parameterize}.pdf",
    "storage" => "store",
    "metadata" => { "filename" => "#{name}.pdf", "size" => bytes, "mime_type" => "application/pdf" }
  }.to_json
  doc
end
