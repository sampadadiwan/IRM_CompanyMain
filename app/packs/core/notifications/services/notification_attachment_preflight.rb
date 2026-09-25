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

  # attached_sizes is {attachment_key => bytes} for what has already been accepted onto this
  # message. A hash rather than a running total because attachments[] is keyed by filename:
  # adding a document whose key is already present REPLACES that part, so the prospective
  # total is the merge, not the sum. Summing blindly would count a 4 MB document matched by
  # two attachment_names entries as 8 MB and refuse a message that is really 4 MB.
  def self.rejection_reason(document, attached_sizes: {})
    size = document_byte_size(document)
    return nil if size.zero?

    return "#{document.name} is #{human(size)} - over the #{human(MAX_ATTACHMENT_BYTES)} limit for a single attachment" if size > MAX_ATTACHMENT_BYTES

    # Within the limit alone; it is the accumulated total that breaches it. Worded
    # differently so the recorded skip_reason is not misleading about which rule fired.
    prospective = attached_sizes.merge(attachment_key(document) => size).values.sum
    return "#{document.name} would take the total over the #{human(MAX_ATTACHMENT_BYTES)} limit for one email" if prospective > MAX_ATTACHMENT_BYTES

    nil
  end

  # Documents are checked per recipient rather than once per send: attachment_names
  # resolves against each recipient's own record (ApplicationMailer#custom_notification_
  # documents_owner), so two recipients on the same send can legitimately receive
  # different documents. Callers pass the set for one email at a time.
  #
  # Accumulates exactly as the mailer does while attaching, so this answers the same
  # question the mailer will answer later, in the same order.
  #
  # Returns [] when the set is sendable, otherwise a list of human-readable problems.
  def self.violations(documents)
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
      reason = rejection_reason(doc, attached_sizes: sizes)
      sizes[attachment_key(doc)] = document_byte_size(doc) if reason.nil?
      reason
    end
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
  def self.batch_error_message(records, custom_notification, context: nil, skip_if: nil)
    problems = []

    each_record(records) do |record|
      next if skip_if&.call(record)

      auto = block_given? ? Array(yield(record)) : []
      problems.concat(violations(auto + custom_notification_documents(custom_notification, record)))
    end

    problems.uniq!
    return nil if problems.blank?

    build_message(problems, context)
  end

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
  def self.report_blocked_send(message, entity_id:, user_id: nil, subject: "Notification not sent")
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

    EntityMailer.with(to:, error_msg: { "Send stopped" => message }, subject:, entity_id:).notify_errors.deliver_later
  rescue StandardError => e
    Rails.logger.error("report_blocked_send failed: #{e.message}")
  end

  # Convenience for callers that just want to stop: returns nil when sendable, or the
  # message to raise/show when not.
  def self.error_message(documents, context: nil)
    problems = violations(documents)
    return nil if problems.empty?

    build_message(problems, context)
  end

  # Shared wording so the operator sees the same explanation whichever check stopped the
  # send, and is told what to do rather than just what failed.
  def self.build_message(problems, context)
    prefix = context.present? ? "#{context}: " : ""
    "#{prefix}#{problems.join('; ')}. " \
      "Email attachments grow by about 37% when encoded, so a larger file is rejected by many " \
      "mail servers. Reduce the file size, or share it from the portal instead."
  end
  private_class_method :build_message

  def self.human(bytes)
    ActiveSupport::NumberHelper.number_to_human_size(bytes)
  end
  private_class_method :human
end
