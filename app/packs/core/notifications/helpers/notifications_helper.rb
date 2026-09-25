module NotificationsHelper
  # A size-aware caution for a send-confirmation dialog.
  #
  # Deliberately says nothing when the attachments are comfortably within the limit: a
  # warning shown on every send is a warning nobody reads. It speaks up only when this
  # particular send would actually be blocked, or is close enough that adding one more
  # document would block it.
  #
  # Uses NotificationAttachmentPreflight so the dialog and the preflight cannot disagree -
  # telling someone their send is fine and then refusing it would be worse than silence.
  # See docs/modules/notifications/attachment_size_limit.md
  def attachment_size_caution(documents)
    docs = Array(documents).compact.uniq
    return nil if docs.empty?

    limit = NotificationAttachmentPreflight::MAX_ATTACHMENT_BYTES
    problems = NotificationAttachmentPreflight.violations(docs)
    total = docs.sum { |doc| NotificationAttachmentPreflight.document_byte_size(doc) }

    if problems.any?
      blocked_attachment_caution(problems, limit)
    elsif total > limit * 0.8
      near_limit_attachment_caution(total, limit)
    end
  end

  # The size of what a Send Document notification would attach: the document itself, plus
  # any documents uploaded onto the notification template. Mirrors DocumentSender.
  def send_document_attachments(document, custom_notification)
    [document] + (custom_notification ? custom_notification.documents.to_a : [])
  end

  private

  def blocked_attachment_caution(problems, limit)
    tag.div(class: "alert alert-danger mt-2 mb-0 p-2 small text-start") do
      safe_join([
                  tag.div(class: "fw-semibold") do
                    safe_join([tag.i(class: "ti ti-alert-triangle me-1"), "This send will be stopped"])
                  end,
                  tag.ul(class: "mb-1 ps-3") { safe_join(problems.map { |p| tag.li(p) }) },
                  tag.div(class: "text-muted") do
                    "Nobody receives it, not just this recipient. Reduce the file below " \
                      "#{number_to_human_size(limit)} or share it from the portal instead."
                  end
                ])
    end
  end

  def near_limit_attachment_caution(total, limit)
    tag.div(class: "alert alert-warning mt-2 mb-0 p-2 small text-start") do
      "Attachments total #{number_to_human_size(total)}, close to the " \
        "#{number_to_human_size(limit)} limit. One more document would stop this send."
    end
  end
end
