# == Schema Information
#
# Table name: messages
#
#  id          :integer          not null, primary key
#  user_id     :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  entity_id   :integer          not null
#  owner_type  :string(255)      not null
#  owner_id    :integer          not null
#  investor_id :integer
#

class Message < ApplicationRecord
  belongs_to :user
  belongs_to :entity
  belongs_to :investor, optional: true
  belongs_to :owner, polymorphic: true

  has_rich_text :content
  # encrypts :content
  validates :content, presence: true
  after_create :broadcast_message

  def broadcast_message
    broadcast_append_to "#{owner_type.underscore}_#{owner_id}",
                        target: "#{owner_type.underscore}_#{owner_id}",
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
