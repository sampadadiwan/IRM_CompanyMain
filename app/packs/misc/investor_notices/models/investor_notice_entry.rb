class InvestorNoticeEntry < ApplicationRecord
  belongs_to :investor_notice
  attr_readonly :investor_notice_id # never moves to another notice (funds_api_security_policy_plan.md, B)
  belongs_to :entity
  belongs_to :investor
  belongs_to :investor_entity, class_name: "Entity", touch: true
end
