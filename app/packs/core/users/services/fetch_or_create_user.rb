class FetchOrCreateUser < Trailblazer::Operation
  step :find_or_create_user

  def find_or_create_user(ctx, email:, first_name:, last_name:, entity_id:, role:, **) # rubocop:disable Metrics/ParameterLists
    user = User.find_by(email: email)
    created_new_user = false

    if user.blank?
      password = SecureRandom.alphanumeric
      user = User.new(first_name: first_name, last_name: last_name,
                      email: email, entity_id: entity_id, password: password)

      if user.valid?
        user.confirm
        created_new_user = user.save
        user.add_role(role) if created_new_user
      else
        ctx[:errors] = user.errors.full_messages.join(", ")
        ctx[:user] = user
        return false
      end
    end
    ctx[:user] = user
    ctx[:created_new_user] = created_new_user
    true
  end
end
