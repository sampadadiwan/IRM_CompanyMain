# Facts-to-confirm grid cells (DocumentReading::STANDARD_COLUMNS keys)
class DocumentReadingDecorator < ApplicationDecorator
  def document_name
    object.document.name
  end

  def input_key
    object.input_key.humanize
  end

  def status
    colour = if object.status == "failed" then "danger"
             elsif object.waiting? then "secondary"
             else
               object.unconfirmed_count.zero? ? "success" : "info"
             end
    h.cmp_badge(object.summary, colour, :fact)
  end

  def sent_at
    object.sent_at ? h.l(object.sent_at.to_date) : "—"
  end

  def created_at
    h.l(object.created_at.to_date)
  end
end
