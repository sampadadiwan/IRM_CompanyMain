class Message < ApplicationRecord
  include ActionView::RecordIdentifier

  # Provides methods like tool_call?, tool_result?
  acts_as_message # Assumes Chat and ToolCall model names
  has_many_attached :attachments

  after_create_commit :broadcast_created, if: :should_broadcast?
  after_update_commit :broadcast_updated, if: :should_broadcast?

  def should_broadcast?
    chat&.enable_broadcast
  end

  private

  def broadcast_created
    broadcast_append_to [chat, "messages"], target: "messages"
  end

  def broadcast_updated
    broadcast_replace_to [chat, "messages"]
  end

  # Helper to broadcast chunks during streaming
  def broadcast_append_chunk(chunk_content)
    html_chunk = ApplicationController.helpers.markdown_to_html(chunk_content)

    Turbo::StreamsChannel.broadcast_append_to(
      [chat, "messages"],               # Stream name
      target: dom_id(self, "content"),  # Append into div#message_123_content
      html: html_chunk                  # Rendered HTML from markdown
    )
  end
end
