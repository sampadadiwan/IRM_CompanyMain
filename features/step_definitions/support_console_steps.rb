# frozen_string_literal: true

# Steps for features/support_console/ — see openspec/changes/archive/2026-10-22-support-console/design.md#worked-examples
# for the shared setup (Meera, Kiran, Priya, Asha; Golden Angels, Beta Capital, Gamma Ventures).

# The console's SupportAgent lives on the CapHive entity; tests create one and point
# CAPHIVE_ENTITY_ID at it for the scenario.
Before("@support_console") do
  @previous_caphive_entity_id = ENV.fetch("CAPHIVE_ENTITY_ID", nil)
  caphive = FactoryBot.create(:entity, name: "CapHive", entity_type: "Company")
  ENV["CAPHIVE_ENTITY_ID"] = caphive.id.to_s
  @support_console_entities = {}
  @support_console_users = {}
end

After("@support_console") do
  ENV["CAPHIVE_ENTITY_ID"] = @previous_caphive_entity_id
end

# @return [Entity] the named client, created on first use
def support_console_entity(name)
  @support_console_entities[name] ||= FactoryBot.create(:entity, name: name, entity_type: "Investment Fund")
end

Given('the client {string} has support access {string}') do |name, state|
  entity = support_console_entity(name)
  state == "on" ? entity.permissions.set(:enable_support) : entity.permissions.unset(:enable_support)
  entity.save!
end

Given('{string} is a support user') do |first_name|
  home = support_console_entity("CapHive Staff")
  @support_console_users[first_name] = FactoryBot.create(:user, entity: home, first_name: first_name).tap { |u| u.add_role(:support) }
end

# :super cannot go through add_role (User#forbid_bad_role aborts it): it is granted by writing the
# join row, as in internal_docs_steps.rb.
Given('{string} is a super user without the support role') do |first_name|
  home = support_console_entity("CapHive Staff")
  user = FactoryBot.create(:user, entity: home, first_name: first_name)
  role = Role.find_or_create_by!(name: "super")
  ActiveRecord::Base.connection.execute(
    ActiveRecord::Base.sanitize_sql_array(["INSERT INTO users_roles (user_id, role_id) VALUES (?, ?)", user.id, role.id])
  )
  @support_console_users[first_name] = user.reload
end

Given('{string} is an employee of {string}') do |first_name, entity_name|
  @support_console_users[first_name] = FactoryBot.create(:user, entity: support_console_entity(entity_name), first_name: first_name)
end

# Inserted directly (not through SupportClientMapping#enable_disable) so the client's
# enable_support permission stays exactly as the scenario set it.
Given('{string} is mapped to {string} until {string}') do |first_name, entity_name, end_date|
  date = { "today" => Time.zone.today, "yesterday" => Time.zone.yesterday, "tomorrow" => Time.zone.tomorrow }
         .fetch(end_date) { Date.parse(end_date) }
  SupportClientMapping.insert!({ user_id: @support_console_users.fetch(first_name).id,
                                 entity_id: support_console_entity(entity_name).id,
                                 enabled: true, end_date: date, created_at: Time.current, updated_at: Time.current })
end

Given("{string}'s mapping to {string} is disabled") do |first_name, entity_name|
  SupportClientMapping.where(user: @support_console_users.fetch(first_name), entity: support_console_entity(entity_name))
                      .update_all(enabled: false)
end

Given('I am logged in as {string}') do |first_name|
  @user = @support_console_users.fetch(first_name)
  log_in(@user)
end

When('I open the Support Console') do
  visit support_console_path
end

When('I open the Support Console for {string}') do |entity_name|
  visit support_console_entity_path(support_console_entity(entity_name))
end

Then('the client picker lists {string}') do |names|
  names.split(",").map(&:strip).each do |name|
    within("ul[aria-labelledby='support-console-picker']", visible: :all) { expect(page).to have_link(name, visible: :all) }
  end
end

Then('the client picker does not list {string}') do |names|
  names.split(",").map(&:strip).each do |name|
    expect(page).to have_no_link(name, visible: :all)
  end
end

Then('I see no client picker') do
  expect(page).to have_no_css("#support-console-picker")
end

Then('I am sent home with {string}') do |message|
  expect(page).to have_current_path(root_path, ignore_query: true)
  expect(page).to have_content(message)
end

# The chat page: its conversation sidebar, with the client named in the header switcher.
Then('I see the conversations for {string}') do |entity_name|
  expect(page).to have_css("#support-console-conversations")
  expect(page).to have_css("#support-console-picker", text: entity_name)
end

# X30, X31 — users of the CapHive entity itself (CAPHIVE_ENTITY_ID), the firm the console's agent belongs to.
Given('{string} works at CapHive') do |first_name|
  @support_console_users[first_name] = FactoryBot.create(:user, entity: Entity.find(ENV.fetch("CAPHIVE_ENTITY_ID")), first_name: first_name)
end

Given('{string} is a support user at CapHive') do |first_name|
  user = FactoryBot.create(:user, entity: Entity.find(ENV.fetch("CAPHIVE_ENTITY_ID")), first_name: first_name)
  @support_console_users[first_name] = user.tap { |u| u.add_role(:support) }
end

When("I post a question to the console's agent through the AI-agent chat route about {string}") do |entity_name|
  page.driver.submit :post, support_agent_chats_path(SupportConsoleAgent.record),
                     { message: "What is the fund size?", chattable_type: "Entity", chattable_id: support_console_entity(entity_name).id }
end

When('I delete that conversation through the AI-agent chat route') do
  page.driver.submit :delete, support_agent_chat_path(@running_session.support_agent, @running_session), {}
end

Then('that conversation still exists') do
  expect(AgentChatSession.exists?(@running_session.id)).to be(true)
end
