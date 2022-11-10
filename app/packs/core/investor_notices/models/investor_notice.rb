class InvestorNotice < ApplicationRecord
  belongs_to :entity
  belongs_to :owner, optional: true, polymorphic: true
  has_many :investor_notice_entries, dependent: :destroy

  has_rich_text :details

  after_save :generate_investor_notice_entries, if: proc { |notice| notice.owner_type != "Entity" }

  def generate_investor_notice_entries
    access_rights.each do |ar|
      ar.investors.each do |investor|
        next if InvestorNoticeEntry.where(investor_id: investor.id, investor_notice_id: id).first.present?

        InvestorNoticeEntry.create!(investor_id: investor.id,
                                    investor_notice_id: id,
                                    investor_entity_id: investor.investor_entity_id,
                                    entity_id:,
                                    active: true)
      end
    end
    nil
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

  def self.notices(investor_entity_id)
    InvestorNotice.joins(:investor_notice_entries).where("investor_notices.active=?", true).where("investor_notice_entries.investor_entity_id=? and investor_notice_entries.active=?", investor_entity_id, true)
  end
end
