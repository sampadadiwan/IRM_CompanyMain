class CustomNotification < ApplicationRecord
  belongs_to :entity
  belongs_to :owner, polymorphic: true

  validates :subject, :body, :whatsapp, presence: true
  validates :whatsapp, :subject, length: { maximum: 255 }

  def to_s
    subject
  end
end
