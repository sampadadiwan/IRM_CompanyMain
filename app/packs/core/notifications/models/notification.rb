class Notification < ApplicationRecord
  include Noticed::Model
  belongs_to :recipient, polymorphic: true, touch: true
  belongs_to :entity
  has_many :whatsapp_logs

  # returns json that contains key entity name from message and value actual entity name
  def self.get_entity_name_json(message, entity_name)
    entity_name_in_msg = message&.downcase&.index("by") ? message&.split(/(?i)(by)/)&.last&.strip : ""
    { entity_name.to_s => entity_name_in_msg }
  end
end
