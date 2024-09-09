module AccessRightsCache
  extend ActiveSupport::Concern

  included do
    # access_rights_cache is a hash serialized, to hold a cache of the users access rights
    # It is updated is access_right is added or deleted for a user
    # This is specifically used for employee and investor_advisor access to data
    # stucture is {owner_type: {owner_id: permissions}}
    # Example {Deal: {1: 7, 2: 6}}, but with a bitmask
    serialize :access_rights_cache, type: Hash

    # Temporary cache of the access rights permissions, used in ApplicationPolicy
    flag :access_rights_cached_permissions, %i[create read update destroy]
  end

  # Return the permissions which are cached
  def get_cached_access_rights_permissions(owner_type, owner_id)
    permissions, metadata = access_rights_cache[owner_type]&.[](owner_id)&.split(",")
    self[:access_rights_cached_permissions] = permissions&.to_i
    [self[:access_rights_cached_permissions], metadata]
  end

  def get_cached_ids(owner_type)
    access_rights_cache[owner_type]&.keys
  end

  # Cache the access rights permissions, called when access_right is added
  def cache_access_rights(access_right, save_by_default: true)
    investor_access = InvestorAccess.where(user_id: id, entity_id: access_right.entity_id).first
    if curr_role == "employee" || investor_access.present?
      access_rights_cache[access_right.owner_type] ||= {}
      access_rights_cache[access_right.owner_type][access_right.owner_id] = "#{access_right[:permissions]}, #{access_right.metadata}"
      save_by_default ? save : false
    else
      Rails.logger.debug { "Not caching access_right, investor access not found for user_id: #{id} and entity_id: #{access_right.entity_id}" }
      false
    end
  end

  def remove_access_rights_cache(access_right, save_by_default: true)
    access_rights_cache[access_right.owner_type]&.delete(access_right.owner_id)
    save_by_default ? save : false
  end

  # This will cleanup and reset all the access_rights for this user
  # Typically called when investor_access is approved or unapproved or deleted
  # optional param entity_id: The entity that is granting investor_access
  def refresh_access_rights_cache(entity_id: nil, add: true)
    # Reset the cache
    self.access_rights_cache = {} if entity_id.blank?

    # Find all the access rights for this user and add/remove from cache
    # This should cover employees and investor_advisors as they have access_rights for specific user
    ars = AccessRight.where(user_id: id)
    ars = ars.where(entity_id:) if entity_id.present?
    ars.each do |ar|
      if add
        cache_access_rights(ar, save_by_default: false)
      else
        remove_access_rights_cache(ar, save_by_default: false)
      end
    end

    unless has_cached_role?(:investor_advisor)
      # Now he may be an investor in many places, via investor_access
      # Note we skip investor_advisors, as they have investor_access,
      # but need access_right for specific user. See above.
      ias = InvestorAccess.where(user_id: id)
      ias = ias.where(entity_id:) if entity_id.present?

      ias.each do |investor_access|
        category = investor_access.investor.category
        # Investor specific access_rights
        access_rights_investor = AccessRight.where(entity_id: investor_access.entity_id, access_to_investor_id: investor_access.investor_id)
        # category specific access_rights
        access_rights_category = AccessRight.where(entity_id: investor_access.entity_id, access_to_category: category)

        # Lets add/remove from cache
        access_rights_investor.or(access_rights_category).find_each do |ar|
          if add
            cache_access_rights(ar, save_by_default: false)
          else
            remove_access_rights_cache(ar, save_by_default: false)
          end
        end
      end
    end

    save
  end
end
