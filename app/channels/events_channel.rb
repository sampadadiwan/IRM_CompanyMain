class EventsChannel < ApplicationCable::Channel
  BROADCAST_CHANNEL = "EventsChannel".freeze
  def subscribed
    stream_from BROADCAST_CHANNEL
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
