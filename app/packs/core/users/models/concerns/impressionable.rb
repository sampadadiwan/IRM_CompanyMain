module Impressionable
  extend ActiveSupport::Concern

  included do
    is_impressionable counter_cache: true, unique: :user_id

    def viewed_by(entity_id: nil)
      ids = impressions.pluck(:user_id).uniq
      if entity_id
        User.where(id: ids, entity_id:)
      else
        User.where(id: ids)
      end
    end
  end
end
