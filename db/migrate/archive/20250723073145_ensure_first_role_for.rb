class EnsureFirstRoleFor < ActiveRecord::Migration[8.0]
  def change
    User.joins(:roles).where(roles: { name: 'investor_advisor' }).find_each do |user|
      if user.advisor_entity_roles.present?
        advisor_entity_roles = user.advisor_entity_roles.split(',').map(&:strip)
        # Ensure the first role is set to 'investor' or employee
        if advisor_entity_roles.first != 'investor' && advisor_entity_roles.first != 'employee'
          # If the first role is not 'investor' or 'employee', prepend 'investor'
          if advisor_entity_roles.include?('investor')
            advisor_entity_roles.delete('investor')
            # Add it to the front of the array
            advisor_entity_roles.unshift('investor')
          end

        end

        user.update_column(:advisor_entity_roles, advisor_entity_roles.join(','))
      end
    end
  end
end
