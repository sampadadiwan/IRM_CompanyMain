class InvestorNoticeItem < ApplicationRecord
  belongs_to :investor_notice
  acts_as_list scope: :investor_notice

  validates :title, :details, presence: true

  before_save :set_entity_id

  def set_entity_id
    self.entity_id = investor_notice.entity_id
  end
end
