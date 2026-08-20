class InvestorNoticeItem < ApplicationRecord
  belongs_to :investor_notice
  acts_as_list scope: :investor_notice

  validates :title, :details, presence: true
  # Dry-run [user.xxx] variables in link at save time (schema-only — see
  # InvestorNoticeLinkInterpolator.validate) so an unsupported path is
  # rejected immediately instead of silently rendering as plain text later.
  validate :link_expression_is_valid, if: -> { link.present? }

  before_save :set_entity_id

  def set_entity_id
    self.entity_id = investor_notice.entity_id
  end

  private

  def link_expression_is_valid
    result = InvestorNoticeLinkInterpolator.validate(link)
    errors.add(:link, "is invalid: #{result}") unless result == true
  end
end
