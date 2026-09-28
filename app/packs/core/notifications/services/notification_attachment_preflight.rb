# Size-checks the documents a notification WOULD attach, before any of it is enqueued.
#
# ApplicationMailer#attachment_allowed? already refuses an oversized attachment at send
# time, but that fires once per recipient, inside a separately-queued job, minutes after
# the operator pressed send (email_delay is a random 1-300s). On its own that turns one
# bad document into N individually-skipped emails discovered long after the fact.
#
# Running the same check up front means the send stops as a single unit and the operator
# is told straight away - DocumentSender raises, and both of its callers already surface
# that (a flash on DocumentsController#send_document_notification, a danger UserAlert on
# DocumentsBulkActionJob#send_document).
#
# The limit and the size lookup both come from ApplicationMailer, so the preflight and the
# send-time guard cannot drift apart on what "too big" means.
#
# Added after a 20.3 MB PDF went to 137 investors at ~28 MB per message and roughly nine
# in ten deliveries bounced - see
# docs/operations/troubleshooting/24092026_peercapital_annual_report_email_bounces.md
class NotificationAttachmentPreflight
  # Largest attachment payload a single email may carry, applied BOTH to each individual
  # document and to their running total. 7 MB of raw file becomes ~9.6 MB once MIME-encoded
  # (AWS documents the overhead as ~137%), which keeps a message under the 10 MB mark above
  # which SES bandwidth-throttles it, and under the 10 MB cap common on corporate mail
  # systems.
  MAX_ATTACHMENT_BYTES = 7.megabytes

  # Byte size WITHOUT downloading the object — Shrine serves this straight from the
  # file_data metadata column. Returns 0 when the size cannot be determined, which lets the
  # attachment through: an unknown size must not silently block a client's mail, and the
  # oversize case we actually care about always has it.
  def self.document_byte_size(document)
    file = document.try(:file)
    return 0 if file.nil?

    (file.respond_to?(:blob) ? file.blob.byte_size : file.size).to_i
  rescue StandardError => e
    Rails.logger.warn("document_byte_size failed for document #{document&.id}: #{e.message}")
    0
  end

  # THE rule, stated once. Why this document cannot go into a message already carrying
  # `bytes_so_far`, or nil if it can.
  #
  # Both enforcement points call this: the batch preflight below, and
  # ApplicationMailer#attachment_allowed? at send time. Expressing it in one place is the
  # point — a preflight that passed something the mailer then refused (or worse, the other
  # way round) would be its own bug.
  # The key ActionMailer will file this document under. attachments[] is a hash keyed by
  # filename, so two documents sharing a name collapse into ONE MIME part — counting both
  # against the limit would measure a message that is never actually built, and refuse a
  # send that would have been fine.
  #
  # Falls back to the bare name if the extension cannot be derived. Document#uploaded_file_extension
  # reads file.metadata and raises outright when the row has no file attached, and this runs on
  # every document the preflight accepts — a read-only size check must not be the thing that
  # takes a whole send down. A name-only key still dedupes correctly; it only loses the
  # extension, which nothing here depends on.
  def self.attachment_key(document)
    extension = begin
      document.uploaded_file_extension
    rescue StandardError
      nil
    end
    "#{document.name}.#{extension}"
  end

  # Which rule this document breaks, and the numbers behind it — nil when it is fine.
  #
  # attached_sizes is {attachment_key => bytes} for what has already been accepted onto this
  # message. A hash rather than a running total because attachments[] is keyed by filename:
  # adding a document whose key is already present REPLACES that part, so the prospective
  # total is the merge, not the sum. Summing blindly would count a 4 MB document matched by
  # two attachment_names entries as 8 MB and refuse a message that is really 4 MB.
  #
  # Split out from the sentence below because the operator's email renders these as TABLE
  # CELLS (document / size / why) while a recorded skip_reason and a flash message need one
  # sentence. Deriving both from this hash keeps them from disagreeing about whether a
  # document is over the limit, which is the one thing about this check that must not vary.
  def self.rejection_detail(document, attached_sizes: {})
    size = document_byte_size(document)
    return nil if size.zero?

    return { document: document.name, size:, rule: :single } if size > MAX_ATTACHMENT_BYTES

    # Within the limit alone; it is the accumulated total that breaches it. Reported
    # differently so neither the skip_reason nor the table is misleading about which rule fired.
    prospective = attached_sizes.merge(attachment_key(document) => size).values.sum
    return { document: document.name, size:, rule: :total, total: prospective } if prospective > MAX_ATTACHMENT_BYTES

    nil
  end

  def self.rejection_reason(document, attached_sizes: {})
    detail = rejection_detail(document, attached_sizes:)
    detail && sentence_for(detail)
  end

  # One-line form, for a Noticed::Notification#skip_reason, a flash, or a log line. The exact
  # wording is depended on by features/fund/*.feature and by rows already written to
  # skip_reason in production, so it is left alone.
  def self.sentence_for(detail)
    case detail[:rule]
    when :single
      "#{detail[:document]} is #{human(detail[:size])} - over the #{human(MAX_ATTACHMENT_BYTES)} limit for a single attachment"
    when :total
      "#{detail[:document]} would take the total over the #{human(MAX_ATTACHMENT_BYTES)} limit for one email"
    end
  end

  # Table-cell form. The document name and its size are their own columns, so this says only
  # WHY, and says it in terms the operator can act on.
  def self.cell_for(detail)
    case detail[:rule]
    when :single
      "Larger than the #{human(MAX_ATTACHMENT_BYTES)} limit for one attachment"
    when :total
      "Together with the other attachments this email reaches #{human(detail[:total])}, " \
      "over the #{human(MAX_ATTACHMENT_BYTES)} limit for one email"
    end
  end
  private_class_method :cell_for

  # Documents are checked per recipient rather than once per send: attachment_names
  # resolves against each recipient's own record (ApplicationMailer#custom_notification_
  # documents_owner), so two recipients on the same send can legitimately receive
  # different documents. Callers pass the set for one email at a time.
  #
  # Accumulates exactly as the mailer does while attaching, so this answers the same
  # question the mailer will answer later, in the same order.
  #
  # Returns [] when the set is sendable, otherwise one rejection_detail hash per refused
  # document. Callers render those as sentences (#violations) or as table rows.
  def self.violation_details(documents)
    docs = Array(documents).compact.uniq
    return [] if docs.empty?

    # Mirrors ApplicationMailer#attachment_allowed? exactly, and it has to:
    #   - bytes are tracked per attachment key, because same-named documents overwrite each
    #     other in attachments[] rather than adding up;
    #   - a REJECTED document contributes nothing to the running total, because the mailer
    #     never attaches it. Counting it would make the next document look oversized too and
    #     name an innocent file in the operator's email.
    sizes = {}
    docs.filter_map do |doc|
      detail = rejection_detail(doc, attached_sizes: sizes)
      sizes[attachment_key(doc)] = document_byte_size(doc) if detail.nil?
      detail
    end
  end

  # The same answer as violation_details, rendered as sentences. Kept because the synchronous
  # single-document path (DocumentSender, FundsController#trigger_adhoc_notification) shows a
  # flash, not a table.
  def self.violations(documents)
    violation_details(documents).map { |detail| sentence_for(detail) }
  end

  # ---------------------------------------------------------------------------
  # Resolving what an email WOULD attach, without attaching it.
  #
  # These moved out of ApplicationMailer so the up-front batch check can ask the same
  # question the mailer asks while sending. ApplicationMailer now delegates to them, so
  # there is still exactly one implementation — a preflight that resolved a different set
  # from the send would be worse than no preflight at all.
  # ---------------------------------------------------------------------------

  # custom_notification.attachment_names, parsed into individual names. CSV.parse_line so a
  # name containing a literal comma (e.g. a date range like "01 July,2025 to 31 December,2025")
  # can be protected by wrapping it in quotes; unquoted entries still split on comma exactly
  # like before. Falls back to a plain comma split if the value has unbalanced quotes, so a
  # typo can't silently drop all attachments.
  def self.attachment_name_list(custom_notification)
    return [] if custom_notification&.attachment_names.blank?

    names = begin
      CSV.parse_line(custom_notification.attachment_names).to_a
    rescue CSV::MalformedCSVError
      custom_notification.attachment_names.split(',')
    end
    names.compact.map(&:strip).compact_blank
  end

  # Converts a '*' wildcard pattern (e.g. "SOA_*_03_2026") into a SQL LIKE pattern,
  # escaping any literal %/_ characters in the non-wildcard parts.
  def self.wildcard_to_like(name)
    name.split('*', -1).map { |part| ActiveRecord::Base.sanitize_sql_like(part) }.join('%')
  end

  # The documents on `owner` matching one attachment_names entry.
  #
  # The PATTERN is squished before use; the stored name is not touched. It doesn't need to be:
  # Document normalizes :name with squish, and migration 20260814100000 backfilled every row
  # written before that, so document names in the database carry no stray whitespace. Squishing
  # the pattern is what covers an attachment_names entry typed or pasted with a doubled space.
  #
  # This deliberately leaves the comparison itself in SQL rather than doing it in Ruby.
  # documents.name is utf8mb4_0900_ai_ci: MySQL treats "Konig" and "König" as equal and gives
  # zero weight to formatting characters, so "- Ishan" matches "- <U+2060>Ishan" — and real
  # document names here contain both accents and zero-width joiners. A Ruby comparison
  # (casecmp?/Regexp) is case-insensitive only, so it would silently stop matching those rows.
  # Keeping the match in the database preserves that behavior exactly, and keeps the relation
  # lazy so latest_doc_only's .limit(1) still becomes a SQL LIMIT instead of loading every match.
  #
  # exclude_generated_unapproved drops a generated-but-unapproved document from the match
  # entirely (regardless of attachment_mandatory) - we never send those. That also means an
  # attachment_names entry whose only match is generated-but-unapproved is treated as absent,
  # so it can trigger missing_mandatory_attachment_names just like a genuinely missing document.
  def self.documents_matching_attachment_name(owner, name)
    pattern = name.to_s.squish
    documents = if pattern.include?('*')
                  owner.documents.where("name like ? ESCAPE ?", wildcard_to_like(pattern), '\\')
                else
                  owner.documents.where(name: pattern)
                end
    documents.exclude_generated_unapproved.order(created_at: :desc)
  end

  # Everything a CustomNotification contributes to one recipient's email: its own uploaded
  # documents, plus whatever attachment_names resolves to against that recipient's record.
  # Mirrors ApplicationMailer#attach_custom_notification_documents exactly.
  def self.custom_notification_documents(custom_notification, owner)
    return [] if custom_notification.nil?

    docs = custom_notification.documents.to_a
    return docs if custom_notification.attachment_names.blank? || !owner.respond_to?(:documents)

    attachment_name_list(custom_notification).each do |name|
      matches = documents_matching_attachment_name(owner, name)
      matches = matches.limit(1) if custom_notification.latest_doc_only
      docs.concat(matches.to_a)
    end
    docs
  end

  # Checks EVERY recipient's own attachment set and returns one combined operator-facing
  # message, or nil when the whole batch is sendable. Callers yield the documents their
  # mailer auto-attaches for a record (attach_all_files and friends); the CustomNotification's
  # contribution is added here.
  #
  # Per record rather than once per send because attachment_names resolves against each
  # recipient's own record, so two recipients on the same send can legitimately receive
  # different documents.
  # find_each rather than Array(records): capital_remittances and capital_distribution_payments
  # are among the tables CLAUDE.md flags as very large, and the callers hand us a relation they
  # deliberately iterate in batches. Materialising it here would undo that and hold every row
  # for the duration of the send.
  # skip_if excludes records this run would not email anyway. It matters: without it an
  # oversized document on an already-notified remittance would permanently block first-time
  # notices for everyone else on the call, and runs that were going to be no-ops would still
  # alert the operator. Use it for conditions that cannot be expressed in SQL (e.g.
  # CapitalCommitment#skip_doc_gen?, which reads a json_fields key); scope the rest into the
  # relation so it never reaches Ruby.
  def self.batch_error_message(records, custom_notification, context: nil, skip_if: nil, email_label: nil)
    problems = []
    rows = []
    checked = 0
    affected = Set.new
    label = email_label.presence || custom_notification&.subject.presence || "-"

    each_record(records) do |record|
      next if skip_if&.call(record)

      checked += 1
      auto = block_given? ? Array(yield(record)) : []
      # Labelled with the record, and NOT uniq'd across records. "Quarterly Report is 10 MB"
      # is useless on a 137-investor send - the operator cannot act on it without knowing
      # whose document it is. Every affected recipient is named so the offending documents
      # can actually be found and fixed.
      violation_details(auto + custom_notification_documents(custom_notification, record))
        .each do |detail|
          affected << record.id
          problems << "#{record} - #{sentence_for(detail)}"
          rows << [label, record.to_s, detail[:document], human(detail[:size]), cell_for(detail)]
        end
    end

    return nil if problems.blank?

    scope = batch_scope(checked, affected.size)
    BlockedSend.new(message: build_message(summarise(problems), context, scope:),
                    headline: flash_headline(problems, context),
                    table: build_table(rows, context, scope))
  end

  # Bounded form, for a flash. The session is a cookie store (4 KB for the WHOLE session), and
  # `message` can name ten recipients - long enough to risk CookieOverflow once anything else is
  # in the session, and far too long to read in a banner either way. Names the first recipient,
  # counts the rest, and points at the email that carries the full table.
  def self.flash_headline(problems, context)
    prefix = context.present? ? "#{context}: " : ""
    extra = problems.size - 1
    more = extra.positive? ? " ...and #{extra} more recipient#{'s' if extra > 1}." : ""
    "#{prefix}#{problems.first}.#{more} Nothing was sent to anyone - the full list is in the " \
      "email just sent to you."
  end
  private_class_method :flash_headline

  # What a blocked batch produces: one sentence for a log line, a flash or an in-app alert,
  # and the same facts as table rows for the operator's email.
  #
  # Callers only ever ask `present?` and hand the result to report_blocked_send, so the two
  # travel together and cannot be reported inconsistently. blank? is pinned to false rather
  # than inherited, so `if blocked.present?` at five call sites cannot quietly change meaning
  # if Struct ever gains an #empty?.
  BlockedSend = Struct.new(:message, :headline, :table, keyword_init: true) do
    def to_s
      message
    end

    def blank?
      false
    end
  end

  # The columns a blocked send is read by: which email, which investor, and why. Size is its
  # own column because "10 MB" sitting next to a 7 MB limit is the whole diagnosis, and the
  # document name is its own column so it can be searched for in the app.
  BLOCKED_TABLE_HEADERS = ["Email", "Investor / Folio", "Document", "Size", "Why it was blocked"].freeze

  def self.build_table(rows, context, scope)
    {
      title: context.presence,
      summary: scope,
      headers: BLOCKED_TABLE_HEADERS,
      rows: rows.first(MAX_LISTED_PROBLEMS),
      footnote: table_footnote(rows.size),
      guidance: "Email attachments grow by about 37% when encoded, so a larger file is rejected " \
                "by many mail servers. Reduce the file size, or share it from the portal instead."
    }
  end
  private_class_method :build_table

  def self.table_footnote(total)
    return nil if total <= MAX_LISTED_PROBLEMS

    extra = total - MAX_LISTED_PROBLEMS
    "...and #{extra} more row#{'s' if extra > 1}, not listed here."
  end
  private_class_method :table_footnote

  # The send is all-or-nothing, so the operator has to be told the RECIPIENTS THEY WERE NOT
  # WARNED ABOUT got nothing either. A message that names only the offending investor reads
  # as "one investor failed", and there is nothing else to correct that impression: the batch
  # enqueues no Noticed::Notification at all, so the notifications list shows neither a sent
  # nor a skipped row for the investors whose documents were perfectly fine.
  def self.batch_scope(checked, affected)
    unaffected = checked - affected
    stopped = "NO emails were sent - the entire send was stopped"
    return "#{stopped}." if unaffected <= 0

    # Deliberately says neither "above" nor "below": this same sentence is the summary line
    # over the email's table AND the tail of the one-line message used for the log, the flash
    # and the in-app alert, where there is no table at all.
    "#{stopped}, including #{unaffected} recipient#{'s' if unaffected > 1} whose attachments were within " \
      "the limit. Fix the oversized document#{'s' if affected > 1} and trigger the notification again to " \
      "send to everyone."
  end
  private_class_method :batch_scope

  # Names every affected recipient up to a point, then counts the rest. A send blocked for
  # 137 investors should say so, without pasting 137 lines into an email.
  MAX_LISTED_PROBLEMS = 10

  def self.summarise(problems)
    return problems if problems.size <= MAX_LISTED_PROBLEMS

    extra = problems.size - MAX_LISTED_PROBLEMS
    problems.first(MAX_LISTED_PROBLEMS) + ["...and #{extra} more recipient#{'s' if extra > 1} with the same problem"]
  end
  private_class_method :summarise

  # Accepts a relation (batched) or a plain array, so callers that already hold records in
  # memory - and the specs - do not have to care.
  def self.each_record(records, &)
    records.respond_to?(:find_each) ? records.find_each(&) : Array(records).each(&)
  end
  private_class_method :each_record

  # Documents an attach_all_files-style mailer (CapitalRemittanceMailer,
  # CapitalDistributionPaymentsMailer) would attach for one record. Mirrors those two
  # methods: generated documents only once approved, plus everything not generated.
  def self.auto_attached_documents(record)
    return [] unless record.respond_to?(:documents)

    record.documents.generated.approved.to_a + record.documents.not_generated.to_a
  end

  # Tells the operator a send was stopped before it started.
  #
  # Background jobs must NOT raise to stop an oversized send — Sidekiq would retry the same
  # doomed batch on a backoff. They call this and return instead. (DocumentSender does raise,
  # because it runs inside the request and both of its callers already turn that into a flash
  # or a UserAlert.)
  #
  # Recipient rule is SkippedNotificationReportJob#recipient_email: whoever triggered it, else
  # the entity's company admins.
  # Accepts the BlockedSend from batch_error_message, or a bare String from the synchronous
  # single-document paths - those have no per-recipient rows to tabulate, so they keep the
  # sentence-and-list email they already had.
  def self.report_blocked_send(blocked, entity_id:, user_id: nil, subject: "Notification not sent")
    message = blocked.to_s
    table = blocked.try(:table)

    # Logged BEFORE working out who to tell. An entity with no company admins and no
    # triggering user would otherwise abort a whole batch leaving no trace anywhere — the
    # operator would just see a send that silently did not happen.
    Rails.logger.error("Notification send blocked (entity #{entity_id}): #{message}")

    to = User.find_by(id: user_id)&.email if user_id.present?
    to ||= User.company_admins.where(entity_id: entity_id).pluck(:email).join(",").presence
    if to.blank?
      Rails.logger.error("No company admin to notify for entity #{entity_id} — send was blocked with no email sent")
      return
    end

    # error_msg is the sentence form the table replaces. Both are passed: an entity_mailer view
    # that renders only the list still says something useful, and a String caller has no table.
    EntityMailer.with(to:, error_msg: { "Send stopped" => message }, error_table: table, subject:,
                      entity_id:).notify_errors.deliver_later

    # An email on its own is a poor place to learn that the button you just pressed did
    # nothing: the batch never enqueues a Noticed::Notification, so there is no skipped row,
    # nothing in the notifications list, and the page still said "trigger started". Broadcast
    # to the operator who pressed it so the failure lands where they are already looking.
    # CapitalDistributionPaymentNotificationJob already did this by hand; doing it here covers
    # every blocked path the same way.
    broadcast_blocked_alert(message, entity_id:, user_id:)
  rescue StandardError => e
    Rails.logger.error("report_blocked_send failed: #{e.message}")
  end

  # Best-effort: an alert that cannot be delivered must never take down the reporting that
  # precedes it, which is the part that actually persists.
  def self.broadcast_blocked_alert(message, entity_id:, user_id:)
    return if user_id.blank?

    UserAlert.new(user_id:, entity_id:, message:, level: "danger").broadcast
  rescue StandardError => e
    Rails.logger.warn("could not broadcast blocked-send alert: #{e.message}")
  end
  private_class_method :broadcast_blocked_alert

  # Convenience for callers that just want to stop: returns nil when sendable, or the
  # message to raise/show when not.
  def self.error_message(documents, context: nil)
    problems = violations(documents)
    return nil if problems.empty?

    build_message(problems, context)
  end

  # Shared wording so the operator sees the same explanation whichever check stopped the
  # send, and is told what to do rather than just what failed.
  def self.build_message(problems, context, scope: nil)
    prefix = context.present? ? "#{context}: " : ""
    ["#{prefix}#{problems.join('; ')}.",
     # Only the batch path knows how many recipients were swept up; the synchronous
     # single-document path (error_message) blocks one email and says so by context.
     scope,
     "Email attachments grow by about 37% when encoded, so a larger file is rejected by many " \
     "mail servers. Reduce the file size, or share it from the portal instead."].compact_blank.join(" ")
  end
  private_class_method :build_message

  def self.human(bytes)
    ActiveSupport::NumberHelper.number_to_human_size(bytes)
  end
  private_class_method :human
end
