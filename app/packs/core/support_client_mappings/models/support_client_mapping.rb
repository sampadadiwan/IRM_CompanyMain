class SupportClientMapping < ApplicationRecord
  include Trackable.new

  # Each SupportClientMapping links a User (the support person)
  # to an Entity (the client they are mapped to).
  belongs_to :user
  belongs_to :entity

  # String representation of the mapping: "<user> - <entity>"
  def to_s
    "#{user} - #{entity}"
  end

  # Class method to remove/disable mappings where end_date has expired.
  # It checks for mappings still enabled but with past end_date.
  def self.disable_expired
    SupportClientMapping.where('enabled = ? and end_date < ?', true, Time.zone.today).find_each(&:disable_support)
  end

  # After any database commit, trigger enable/disable cascade actions.
  after_commit :enable_disable

  # Ensure the support state of associated entity/users matches this mapping.
  def enable_disable
    if enabled
      enable_support
    else
      disable_support
    end
  end

  # Enables support for the entity and all its employees.
  # - Marks this mapping as enabled.
  # - Sets `:enable_support` permission on the entity.
  # - Updates all associated employees to have support enabled.
  def enable_support
    update_column(:enabled, true)
    entity.permissions.set(:enable_support)
    entity.save
    entity.employees.each do |user|
      user.update_column(:enable_support, true)
    end
  end

  # Disables support for the entity and all its employees.
  # - Marks this mapping as disabled.
  # - Removes `:enable_support` permission on the entity.
  # - Updates all associated employees to disable support.
  def disable_support
    update_column(:enabled, false)
    entity.permissions.unset(:enable_support)
    entity.save
    entity.employees.each do |user|
      user.update_column(:enable_support, false)
    end
  end

  # Switches current user context to mapped entity.
  # - Caches original entity and roles in json_fields.
  # - Changes user entity_id to mapped entity.
  # - Grants company_admin role and removes support role.
  # Raises error if mapping is currently disabled.
  def switch
    if enabled && entity.enable_support
      user.json_fields ||= {}
      user.json_fields['orig_entity_id'] ||= user.entity_id
      user.json_fields['orig_roles'] ||= user.roles.pluck(:name)
      user.update_columns(entity_id: entity.id, json_fields: user.json_fields, entity_type: entity.entity_type)
      user.add_role(:company_admin)
    else
      raise 'Cannot switch a disabled mapping'
    end
  end

  # Reverts a user back to their original entity and roles.
  # - Restores previous entity_id from cached json_fields.
  # - Restores original roles.
  # - Re-adds support role and removes company_admin role.
  # Raises error if no previous entity or if mapping is disabled.
  def revert
    if enabled
      orig_entity_id = user.json_fields['orig_entity_id']
      orig_entity = Entity.find_by(id: orig_entity_id)
      orig_roles = user.json_fields['orig_roles'] || []
      if orig_entity_id.present?
        user.update_columns(entity_id: orig_entity_id, entity_type: orig_entity.entity_type)
        user.add_role(:support)
        user.remove_role(:company_admin)
        orig_roles.each do |role|
          user.add_role(role) unless user.has_role?(role)
        end
      else
        raise 'No previous entity to revert to'
      end
    else
      raise 'Cannot revert a disabled mapping'
    end
  end

  def status
    if user.json_fields.present? && user.json_fields['orig_entity_id'].present? && user.json_fields['orig_entity_id'] != user.entity_id
      'Switched'
    else
      'Reverted'
    end
  end

  def allow_login_as(email)
    if user_emails.present?
      enable_user_login && user_emails.split(',').map(&:strip).include?(email)
    else
      enable_user_login
    end
  end
end
