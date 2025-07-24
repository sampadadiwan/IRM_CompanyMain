module WithFriendlyId
  extend ActiveSupport::Concern

  included do
    extend FriendlyId

    friendly_id :for_friendly_id, use: :slugged
    def to_param
      id
    end
  end

  def for_friendly_id
    to_s ? "#{self}-#{id}" : nil
  end
end
