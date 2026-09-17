# Files one email against an owner record, for the Outlook task pane and the Gmail add-on.
#
# This is the single write path for both add-ins. Everything that previously lived in the
# clients — and diverged between them — happens here instead, so an email filed from
# Outlook and the same email filed from Gmail produce the same record.
#
# Idempotent on internet_message_id (the RFC 5322 Message-ID) scoped to the owner. Re-filing
# returns the existing record with `already_filed` set rather than creating a duplicate, so
# a double click, a slow network retry, or a second colleague filing the same thread is
# harmless. The clients previously had no dedup at all.
#
# @see docs/technical/mail_addin_review.md
class MailFilingCreate < Trailblazer::Operation
  step :authorize_owner
  step :find_existing
  step :build_email
  step :save_email
  left :handle_errors, Output(:failure) => End(:failure)
  step :attach_documents

  # Filing records correspondence rather than mutating the owner, so it is gated on
  # file_mail? — see InvestorPolicy#file_mail?.
  def authorize_owner(ctx, user:, owner:, **)
    unless Pundit.policy!(user, owner).file_mail?
      ctx[:errors] = "You do not have permission to file email against this record."
      return false
    end
    true
  end

  # Dedup lookup. Skipped when the client could not supply a Message-ID, in which case
  # duplicates remain possible but are no worse than before.
  def find_existing(ctx, owner:, attributes:, **)
    internet_message_id = attributes[:internet_message_id].presence
    return true if internet_message_id.blank?

    ctx[:incoming_email] = IncomingEmail.find_by(
      entity_id: owner.entity_id,
      internet_message_id: internet_message_id,
      owner_type: owner.class.name,
      owner_id: owner.id
    )
    ctx[:already_filed] = ctx[:incoming_email].present?
    true
  end

  def build_email(ctx, user:, owner:, attributes:, **)
    return true if ctx[:already_filed]

    ctx[:incoming_email] = IncomingEmail.new(attributes.except(:attachments))
    ctx[:incoming_email].owner = owner
    ctx[:incoming_email].entity = owner.entity
    ctx[:incoming_email].filed_by_user = user
    ctx[:incoming_email].received_at ||= Time.current
    true
  end

  def save_email(ctx, **)
    return true if ctx[:already_filed]

    ctx[:incoming_email].save
  rescue ActiveRecord::RecordNotUnique
    # Lost a race against a concurrent identical filing. The unique dedup index did its
    # job; adopt the row the other request created and report success.
    ctx[:incoming_email] = IncomingEmail.find_by(
      entity_id: ctx[:incoming_email].entity_id,
      internet_message_id: ctx[:incoming_email].internet_message_id,
      owner_type: ctx[:incoming_email].owner_type,
      owner_id: ctx[:incoming_email].owner_id
    )
    ctx[:already_filed] = true
    ctx[:incoming_email].present?
  end

  def handle_errors(ctx, **)
    email = ctx[:incoming_email]
    ctx[:errors] ||= email&.errors&.full_messages&.join(", ").presence || "Could not file this email."
    Rails.logger.error "MailFilingCreate failed: #{ctx[:errors]}"
    false
  end

  # Attachments are what make a filed email useful — side letters, wire confirmations,
  # signed subscription documents. Neither add-in filed them before.
  #
  # Runs even when the email was already filed. A client retrying after a lost response is
  # the normal way this operation is re-entered, and skipping attachments on that path
  # meant a retry reported success while quietly filing nothing — the attachments would be
  # lost if the original request died before reaching this step. Files already present are
  # skipped by name so a retry does not duplicate them.
  def attach_documents(ctx, user:, attachments: nil, **)
    return true if attachments.blank?

    email = ctx[:incoming_email]
    existing_names = email.documents.pluck(:name).to_set
    pending = Array(attachments).compact.reject { |file| existing_names.include?(file.original_filename) }
    return true if pending.empty?

    failures = email.save_uploaded_attachments(pending, user: user)
    # Surfaced rather than swallowed: a rejected attachment (file type, size) previously
    # left the caller reporting a clean success with the document missing.
    ctx[:attachment_errors] = failures if failures.any?
    true
  end
end
