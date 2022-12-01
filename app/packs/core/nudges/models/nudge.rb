# == Schema Information
#
# Table name: nudges
#
#  id         :integer          not null, primary key
#  to         :text(65535)
#  subject    :text(65535)
#  msg_body   :text(65535)
#  user_id    :integer          not null
#  entity_id  :integer          not null
#  item_type  :string(255)
#  item_id    :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  cc         :text(65535)
#  bcc        :text(65535)
#

class Nudge < ApplicationRecord
  belongs_to :user
  belongs_to :entity
  belongs_to :item, polymorphic: true, optional: true
  has_many :access_rights, as: :owner, dependent: :destroy

  has_rich_text :msg_body

  after_create_commit :send_nudge
  def send_nudge
    NudgeMailer.with(id:).send_nudge.deliver_later
  end

  def pre_populate
    self.to = []
    self.cc = entity.employees.collect(&:email).join(",")
    self.subject = ""
    self.msg_body = ""
    case item_type
    when "DealActivity"
      ia = item.deal_investor.investor.investor_accesses.approved
      self.to = ia.collect(&:email).join(",")
      self.subject = "Task #{item.title} is pending"
      self.msg_body = "Dear Investor, Please can you complete this task"
    when "DealInvestor"
      ia = item.investor.investor_accesses.approved
      self.to = ia.collect(&:email).join(",")
    end
  end
end
