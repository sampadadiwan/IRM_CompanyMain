# We have multiple combinations to grant access
# 1. company_admin: Can see evertything in his entity
# 2. employee: Can see everything in his entity, that he is given access_rights to, no investor access required
# 3. fund investor_advisor: Can see everything that he is given access_rights to by fund, and investor access required from the fund
# 4. investor investor_advisor: Can see everything that he is given access_rights to by the investor, and investor access required from the fund

############################################################################################
# Role                       # Access Rights                      # Investor Access   # Visibility #
# company_admin              # Not Required                       # Not Required      # All #
# employee                   # Required                           # Not Required      # Specific #
# fund investor_advisor      # Required (From fund entity)        # Required (From fund entity) # Specific #
# investor investor_advisor  # Required (From investor entity)    # Required (From fund entity) # Specific #
############################################################################################

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
  def get_cached_access_rights_permissions(entity_id, owner_type, owner_id)
    cache = access_rights_cache

    # Direct lookup if entity_id is provided
    if entity_id
      value = cache.dig(entity_id, owner_type, owner_id)
      permissions, metadata = value&.split(",")
      self[:access_rights_cached_permissions] = permissions&.to_i
      return [self[:access_rights_cached_permissions], metadata&.strip]
    end

    # entity_id is nil: search across all entity_ids
    cache.each_value do |types|
      next unless types[owner_type]

      value = types[owner_type][owner_id]
      next unless value

      permissions, metadata = value.split(",")
      self[:access_rights_cached_permissions] = permissions.to_i
      return [self[:access_rights_cached_permissions], metadata.strip]
    end

    # Not found
    [nil, nil]
  end

  def get_cached_ids(entity_id, owner_type)
    if entity_id.present?
      access_rights_cache.dig(entity_id, owner_type)&.keys || []
    else
      # Return all the ids for this owner_type, across all entity_ids
      access_rights_cache[owner_type]&.values&.map(&:keys)&.flatten || []
    end
  end

  # Cache the access rights permissions, called when access_right is added
  # access_right: The access_right object that is added
  # save_by_default: Save the user object by default, if true
  # for_entity_id: The entity_id for which the access_right is added in the cache
  # investor_access: The investor_access object, if present (to optimize calls from refresh_access_rights_cache)
  def cache_access_rights(access_right, save_by_default: true, for_entity_id: nil, investor_access: nil)
    investor_access ||= InvestorAccess.where(user_id: id, entity_id: access_right.entity_id).first
    # Initialize the cache
    for_entity_id = access_right.entity_id if for_entity_id.blank? || access_right.user_id.present?
    self.access_rights_cache ||= {}
    self.access_rights_cache[for_entity_id] ||= {}
    self.access_rights_cache[for_entity_id][access_right.owner_type] ||= {}
    self.access_rights_cache[for_entity_id][access_right.owner_type][access_right.owner_id] ||= {}
    # Cache only if the user is an employee or has investor access
    if curr_role == "employee" || investor_access.present?
      self.access_rights_cache[for_entity_id][access_right.owner_type][access_right.owner_id] = "#{access_right[:permissions]}, #{access_right.metadata}"
      save_by_default ? save : false
    else
      # If the user is not an employee or investor, then do not cache
      Rails.logger.debug { "Not caching access_right, investor access not found for user_id: #{id} and entity_id: #{for_entity_id}" }
      false
    end
  end

  def remove_access_rights_cache(access_right, save_by_default: true, for_entity_id: nil)
    for_entity_id ||= access_right.entity_id
    access_rights_cache.dig(for_entity_id, access_right.owner_type)&.delete(access_right.owner_id)
    save_by_default ? save : false
  end

  # This will cleanup and reset all the access_rights for this user
  # Typically called when investor_access is approved or unapproved or deleted
  # optional param entity_id: The entity that is granting investor_access
  def refresh_access_rights_cache(investor_access, add: true)
    # Reset the cache
    self.access_rights_cache = {} if entity_id.blank?

    # Find all the access rights for this user and add/remove from cache
    # This should cover employees and investor_advisors as they have access_rights for specific user
    ars = AccessRight.where(user_id: id)
    ars = ars.where(entity_id: investor_access.entity_id).or(ars.where(entity_id: investor_access.investor_entity_id))
    ars.each do |ar|
      if add
        cache_access_rights(ar, save_by_default: false, for_entity_id: investor_access.investor_entity_id, investor_access:)
      else
        remove_access_rights_cache(ar, save_by_default: false, for_entity_id: investor_access.investor_entity_id)
      end
    end

    access_rights_to_add = []

    unless has_cached_role?(:investor_advisor)

      category = investor_access.investor.category
      # Investor specific access_rights
      access_rights_investor = AccessRight.where(entity_id: investor_access.entity_id, access_to_investor_id: investor_access.investor_id)
      # category specific access_rights
      access_rights_category = AccessRight.where(entity_id: investor_access.entity_id, access_to_category: category)

      # Lets add/remove from cache
      access_rights_to_add = access_rights_investor.or(access_rights_category)

    end

    access_rights_to_add.each do |ar|
      if add
        cache_access_rights(ar, save_by_default: false, for_entity_id: investor_access.investor_entity_id, investor_access:)
      else
        remove_access_rights_cache(ar, save_by_default: false, for_entity_id: investor_access.investor_entity_id)
      end
    end

    save
  end

  def reset_access_rights_cache
    self.access_rights_cache = {}
    if has_cached_role?(:company_admin)
      # Nothing to do as company_admin has access to everything
    elsif has_cached_role?(:employee) && !has_cached_role?(:investor) && !has_cached_role?(:investor_advisor)
      # Add all the access rights for this user
      AccessRight.where(user_id: id).find_each do |ar|
        cache_access_rights(ar, save_by_default: false)
      end
      save
    elsif has_cached_role?(:investor) || has_cached_role?(:investor_advisor)
      # Add all the investor_access
      InvestorAccess.approved.where(user_id: id).find_each do |investor_access|
        refresh_access_rights_cache(investor_access, add: true)
      end
    end
  end
end
