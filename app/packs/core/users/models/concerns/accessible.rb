module Accessible
  extend ActiveSupport::Concern

  included do
    scope :for_access_type, ->(type) { where("access_rights.access_type=?", type) }
    scope :investor_access, ->(investor) { where("(access_rights.access_to_investor_id=? OR access_rights.access_to=?)", investor.id, investor.category) }
  end
end
