# == Schema Information
#
# Table name: messages
#
#  id               :integer          not null, primary key
#  user_id          :integer          not null
#  deal_investor_id :integer          not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  task_done        :boolean          default("0")
#  deleted_at       :datetime
#  not_msg          :boolean          default("0")
#  entity_id        :integer          not null
#

class Message < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  belongs_to :owner, polymorphic: true
  has_rich_text :content
  # encrypts :content
  validates :content, presence: true

  scope :msg, -> { where(not_msg: false) }

  after_create :broadcast_message, unless: :not_msg

  def broadcast_message
    broadcast_append_to "#{owner_type}_#{owner_id}",
                        target: "#{owner_type}_#{owner_id}",
                        partial: "messages/conversation_msg", locals: { msg: self }
  end

  def unread(user); end

  after_create :update_message_count
  def update_message_count
    if owner_type == "DealInvestor"
      deal_investor = owner
      if user.entity_id == deal_investor.entity_id
        deal_investor.unread_messages_investor += 1
        deal_investor.todays_messages_investor += 1
      else
        deal_investor.unread_messages_investee += 1
        deal_investor.todays_messages_investee += 1
      end

      deal_investor.save
    end
  end
end
