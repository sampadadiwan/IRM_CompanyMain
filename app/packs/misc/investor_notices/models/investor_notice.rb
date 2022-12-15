class InvestorNotice < ApplicationRecord
  belongs_to :entity
  belongs_to :owner, optional: true, polymorphic: true
  has_many :investor_notice_entries, dependent: :destroy

  has_rich_text :details

  validates :title, :start_date, :end_date, :details, presence: true

  after_commit :generate_investor_notice_entries, if: proc { |notice| notice.generate && notice.saved_change_to_generate? }

  def generate_investor_notice_entries
    InvestorNoticeJob.perform_later(id)
  end

  def access_rights
    ars = owner.access_rights
    ars = ars.where(metadata: access_rights_metadata) if access_rights_metadata.present?
    ars
  end

  def investors
    if owner_type == "Entity"
      owner.investors
    else
      access_rights.collect(&:investors).flatten
    end
  end

  def self.notices(user)
    InvestorNotice.joins(:investor_notice_entries, entity: :investor_accesses).where("investor_notices.active=?", true)
                  .where("investor_notice_entries.investor_entity_id=? and investor_notice_entries.active=?", user.entity_id, true)
                  .where("investor_accesses.user_id=? and investor_accesses.approved=?", user.id, true)
  end
end
