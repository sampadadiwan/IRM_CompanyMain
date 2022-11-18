class InvestorNoticeEntry < ApplicationRecord
  belongs_to :investor_notice
  belongs_to :entity
  belongs_to :investor
  belongs_to :investor_entity, class_name: "Entity", touch: true
end
