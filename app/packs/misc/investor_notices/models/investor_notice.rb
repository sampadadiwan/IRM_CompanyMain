class InvestorNotice < ApplicationRecord
  belongs_to :entity
  belongs_to :owner, optional: true, polymorphic: true
  has_many :investor_notice_entries, dependent: :destroy
  has_many :investor_notice_items, dependent: :destroy
  accepts_nested_attributes_for :investor_notice_items, reject_if: :all_blank, allow_destroy: true

  has_rich_text :details

  validates :title, :start_date, :end_date, presence: true
  validates :btn_label, length: { maximum: 40 }
  validates :category, length: { maximum: 30 }

  after_commit :update_investors
  after_commit :generate_investor_notice_entries, if: proc { |notice| notice.generate && notice.saved_change_to_generate? }

  def generate_investor_notice_entries
    InvestorNoticeJob.perform_later(id)
  end

  def update_investors
    # Bust the cache for this notice for all investor_entity_ids, see carousel is cached based on that
    investor_entity_ids = investor_notice_entries.collect(&:investor_entity_id)
    Entity.where(id: investor_entity_ids).update_all(updated_at: Time.zone.now)
  end

  def access_rights
    ars = owner.access_rights
    ars = ars.where(metadata: access_rights_metadata) if access_rights_metadata.present?
    ars
  end

  delegate :investors, to: :owner

  def self.notices(user)
    InvestorNotice.joins(:investor_notice_entries, entity: :investor_accesses).where("investor_notices.active=?", true)
                  .where("investor_notice_entries.investor_entity_id=? and investor_notice_entries.active=?", user.entity_id, true)
                  .where("investor_accesses.user_id=? and investor_accesses.approved=?", user.id, true)
  end
end
