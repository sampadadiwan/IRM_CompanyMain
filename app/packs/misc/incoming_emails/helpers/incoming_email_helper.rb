module IncomingEmailHelper
  def format_email_body(body)
    formatted_body = body
                     .gsub(/(?:\r\n|\r|\n)/, '<br>')  # Convert line breaks to <br>
                     .gsub(/(\d+\.)\s+/, '<br>\1 ')   # Handle ordered lists
                     .gsub(/\*(.*?)\*/, '<b>\1</b>')  # Handle bold text
                     .gsub(/_(.*?)_/, '<i>\1</i>') # Handle italic text

    simple_format(formatted_body, {}, sanitize: false)
  end
end
