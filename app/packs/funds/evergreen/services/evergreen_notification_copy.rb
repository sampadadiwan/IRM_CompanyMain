# Copies a fund's investor-email templates (CustomNotification for_type "Evergreen") to another
# evergreen fund of the same entity. Emails the target already customises are skipped — nothing is
# overwritten. Files attached to a template (its document folder) are not copied.
# open-ended-funds § Notifications
class EvergreenNotificationCopy
  COPIED = %w[subject body email_method for_type enabled show_details show_details_link is_erb whatsapp tag
              attachment_names attachment_mandatory attachment_password password_protect_attachment latest_doc_only].freeze

  # Other evergreen funds of the entity that have at least one Evergreen template
  def self.sources(fund)
    ids = CustomNotification.where(owner_type: "Fund", for_type: "Evergreen", enabled: true, latest: true, entity_id: fund.entity_id)
                            .where.not(owner_id: fund.id).distinct.pluck(:owner_id)
    Fund.where(id: ids).order(:name).select(&:evergreen?)
  end

  # Returns [copied, skipped]
  def self.call(from:, to:)
    raise ArgumentError, "Choose a fund of the same entity" unless from.entity_id == to.entity_id

    existing = to.custom_notifications.where(for_type: "Evergreen").pluck(:email_method)
    copied = 0
    skipped = 0
    # The template in use for each email: enabled and latest
    from.custom_notifications.enabled.where(for_type: "Evergreen", latest: true).order(:id).find_each do |cn|
      if existing.include?(cn.email_method)
        skipped += 1
        next
      end
      CustomNotification.create!(cn.attributes.slice(*COPIED).merge(entity_id: to.entity_id, owner: to))
      existing << cn.email_method
      copied += 1
    end
    [copied, skipped]
  end
end
