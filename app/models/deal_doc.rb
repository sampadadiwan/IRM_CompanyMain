# == Schema Information
#
# Table name: deal_docs
#
#  id                :integer          not null, primary key
#  name              :string(255)
#  deal_id           :integer          not null
#  deal_investor_id  :integer
#  deal_activity_id  :integer
#  user_id           :integer          not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  file_file_name    :string(255)
#  file_content_type :string(255)
#  file_file_size    :integer
#  file_updated_at   :datetime
#  deleted_at        :datetime
#  impressions_count :integer          default("0")
#

class DealDoc < ApplicationRecord
  include Trackable
  include Impressionable

  acts_as_taggable_on :tags

  belongs_to :deal
  belongs_to :deal_investor, optional: true
  belongs_to :deal_activity, optional: true
  belongs_to :user

  delegate :investor_name, to: :deal_investor
  delegate :name, to: :deal, prefix: :deal
  delegate :title, to: :deal_activity, prefix: :deal_activity

  validates :name, presence: true

  has_attached_file :file,
                    s3_permissions: nil,
                    bucket: proc { |attachment|
                      attachment.instance.deal.entity.s3_bucket.presence || "#{ENV['AWS_S3_BUCKET']}.#{Rails.env}"
                    }

  validates_attachment_content_type :file, content_type: [%r{\Aimage/.*\Z}, %r{\Avideo/.*\Z}, %r{\Aaudio/.*\Z}, %r{\Aapplication/.*\Z}]

  validates_attachment :file, presence: true,
                              size: { in: 0..(10.megabytes) }

  scope :user_deal_docs, lambda { |user|
                           where("deal_docs.user_id =? OR deals.entity_id=? OR
                                  deal_investors.entity_id=? OR investors.investor_entity_id=?",
                                 user.id, user.entity_id, user.entity_id, user.entity_id)
                             .left_outer_joins(:deal, deal_investor: [:investor])
                             .includes(:deal, deal_investor: :investor)
                         }

  scope :only_deal_docs, -> { where(deal_docs: { deal_investor_id: nil }) }
  scope :deal_investor_docs, ->(deal_investor) { where("deal_docs.deal_investor_id=?", deal_investor.id) }
  scope :deal_activity_docs, ->(deal_activity) { where("deal_docs.deal_activity_id=?", deal_activity.id) }

  before_save :update_deal_investor
  def update_deal_investor
    self.deal_investor_id = deal_activity.deal_investor_id if deal_activity.present?
  end

  def to_s
    name
  end
end
