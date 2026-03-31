Given('the default support email is {string}') do |email|
  ENV['SUPPORT_EMAIL_TO'] = email
end

Given('a support mapping exists for entity {string} and user {string}') do |entity_name, user_email|
  entity = Entity.find_by(name: entity_name)
  user = User.find_by(email: user_email)
  FactoryBot.create(:support_client_mapping, entity: entity, user: user, enabled: true)
end

When('I trigger {string} with {string}') do |mailer_method, args|
  params = {}
  args.split(';').each do |arg|
    key, value = arg.split('=')
    if key == 'entity_id'
      entity = Entity.find_by(name: value)
      value = entity&.id
    elsif %w[msg error_msg].include?(key)
      # Convert "key:value" to { "key" => "value" }
      h = {}
      value.split(',').each do |pair|
        k, v = pair.split(':')
        h[k] = v
      end
      value = h
    end
    params[key.to_sym] = value
  end
  EntityMailer.with(params).send(mailer_method).deliver_now
end

Then('an email should not be sent to {string}') do |email|
  open_email(email)
  expect(current_email).to be_nil
end
