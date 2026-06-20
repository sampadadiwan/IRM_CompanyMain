# Step definitions for workflow_magic_links.feature

# ── Setup helpers ─────────────────────────────────────────────────────────────

Given("there is an actor user {string} in the entity") do |email|
  first_name, last_name = email.split("@").first.capitalize, "Actor"
  @actor_user = User.find_or_initialize_by(email: email, entity: @entity)
  @actor_user.assign_attributes(
    first_name: first_name,
    last_name:  last_name,
    password:   "password123"
  )
  @actor_user.save!
end

# Overrides resolve_actor_list so "actor_user" label resolves to @actor_user
alias_method :original_resolve_actor_list, :resolve_actor_list rescue nil
def resolve_actor_list(actors_str)
  return [@user] if actors_str.blank?
  actors_str.split(",").map(&:strip).map do |label|
    case label
    when "admin"      then @user
    when "actor2"     then @actor2
    when "actor_user" then @actor_user
    else User.find_by!(email: label, entity: @entity)
    end
  end.compact
end

Given("the instance is now at step {int}") do |step_pos|
  # @instance is set by the preceding "has an active workflow instance" step; fall back to searching
  @instance ||= @entity.folders.flat_map { |f| f.workflow_instances.instance_active.to_a }.first
  @instance.update!(current_step_position: step_pos)
end

# ── Token helpers ─────────────────────────────────────────────────────────────

When("I generate a magic link token for actor {string} instance {int} step {int}") do |email, instance_id, step|
  actor  = User.find_by!(email: email, entity: @entity)
  @token = WorkflowMagicLinkService.new.generate_token(
    actor_id:      actor.id,
    instance_id:   instance_id,
    step_position: step
  )
end

When("I verify a tampered magic link token") do
  @verified_payload = WorkflowMagicLinkService.new.verify_token("invalid.tampered.token")
end

Then("I can verify the token and recover the payload") do
  @verified_payload = WorkflowMagicLinkService.new.verify_token(@token)
  @verified_payload.should_not be_nil
end

Then("the payload actor_id matches {string}") do |email|
  actor = User.find_by!(email: email, entity: @entity)
  @verified_payload[:actor_id].to_i.should == actor.id
end

Then("the token verification should return nil") do
  @verified_payload.should be_nil
end

# ── Email enqueueing ──────────────────────────────────────────────────────────

Then("a step activation email should be enqueued for {string}") do |email|
  actor     = User.find_by!(email: email, entity: @entity)
  # :inline adapter delivers synchronously into ActionMailer::Base.deliveries
  delivered = ActionMailer::Base.deliveries.any? { |mail| mail.to.include?(actor.email) }
  delivered.should == true
end

# ── Magic link page ───────────────────────────────────────────────────────────

When("I visit the magic link for actor {string} on the active instance at step {int}") do |email, step|
  actor     = User.find_by!(email: email, entity: @entity)
  @instance ||= @entity.folders.flat_map { |f| f.workflow_instances.instance_active.to_a }.first
  @token    = WorkflowMagicLinkService.new.generate_token(
    actor_id:      actor.id,
    instance_id:   @instance.id,
    step_position: step
  )
  @ml_result = WorkflowMagicLinkService.new.verify_token(@token)
end

When("I visit the magic link page with token {string}") do |token|
  @token     = token
  @ml_result = WorkflowMagicLinkService.new.verify_token(token)
end

Then("the magic link page should show the response form") do
  # Verify token decodes and the instance step matches
  @ml_result.should_not be_nil
  @instance ||= WorkflowInstance.find(@ml_result[:instance_id])
  @instance.current_step_position.should == @ml_result[:step_position].to_i
end

Then("the response form should list state {string}") do |state|
  @instance ||= WorkflowInstance.find(@ml_result[:instance_id])
  step = @instance.current_step_data
  states = step[:states].to_s.split(",").map(&:strip)
  states.should include(state)
end

Then("the magic link page should show the moved-on message") do
  # The step in the token no longer matches the instance's current step
  @ml_result.should_not be_nil
  @instance ||= WorkflowInstance.find(@ml_result[:instance_id])
  @instance.current_step_position.should_not == @ml_result[:step_position].to_i
end

# Simulates the controller's verify_magic_link_token guards and records the routing decision
# and the @previous_response lookup — mirrors WorkflowMagicLinkController#verify_magic_link_token
When("I evaluate the magic link routing for actor {string} on the instance at step {int}") do |email, step|
  actor  = User.find_by!(email: email)
  # @instance is set by a preceding submit step; fall back to any non-archived instance for the entity
  inst   = @instance || @entity.folders.flat_map { |f| f.workflow_instances.where.not(status: :archived).to_a }.first
  raise "No workflow instance found" unless inst

  token  = WorkflowMagicLinkService.new.generate_token(
    actor_id:      actor.id,
    instance_id:   inst.id,
    step_position: step
  )
  payload = WorkflowMagicLinkService.new.verify_token(token)

  unless payload
    @ml_routing           = :invalid
    @ml_previous_response = nil
    next
  end

  resolved_instance = WorkflowInstance.find_by(id: payload[:instance_id])
  unless resolved_instance
    @ml_routing           = :invalid
    @ml_previous_response = nil
    next
  end

  unless resolved_instance.instance_active?
    @ml_previous_response = resolved_instance.workflow_actor_responses
                                             .for_step(payload[:step_position].to_i)
                                             .find_by(actor_id: payload[:actor_id])
    @ml_routing = :moved_on
    next
  end

  if payload[:step_position].to_i != resolved_instance.current_step_position
    @ml_previous_response = resolved_instance.workflow_actor_responses
                                             .for_step(payload[:step_position].to_i)
                                             .find_by(actor_id: payload[:actor_id])
    @ml_routing = :moved_on
    next
  end

  @ml_routing           = :show
  @ml_previous_response = nil
end

Then("the magic link routing should be {string}") do |expected|
  @ml_routing.to_s.should == expected
end

Then("the magic link previous response for {string} should exist") do |_email|
  @ml_previous_response.should_not be_nil
end

Then("the magic link previous response for {string} should not exist") do |_email|
  @ml_previous_response.should be_nil
end

Then("the magic link page should show the invalid message") do
  @ml_result.should be_nil
end

# ── Magic link submit ─────────────────────────────────────────────────────────

When("I submit {string} via magic link for actor {string} on step {int} of the active instance") do |state, email, step|
  actor     = User.find_by!(email: email, entity: @entity)
  @instance ||= @entity.folders.flat_map { |f| f.workflow_instances.instance_active.to_a }.first
  @token    = WorkflowMagicLinkService.new.generate_token(
    actor_id:      actor.id,
    instance_id:   @instance.id,
    step_position: step
  )
  @submit_error = nil
  begin
    response = WorkflowActorResponse.create!(
      workflow_instance: @instance,
      actor:             actor,
      step_position:     step,
      channel:           :email_magic_link,
      responded_at:      Time.current,
      state:             state
    )
    result = WorkflowStepResolver.resolve(@instance.reload)
    WorkflowAdvancer.advance(@instance, resolved_state: result[:resolved],
                             actor: actor, channel: :email_magic_link) if result[:resolved]
    @last_magic_link_response = response
  rescue ActiveRecord::RecordInvalid => e
    @submit_error = e.message
  end
end

When("I try to submit {string} via magic link for actor {string} on step {int} of the active instance again") do |state, email, step|
  actor = User.find_by!(email: email, entity: @entity)
  @submit_error = nil
  begin
    WorkflowActorResponse.create!(
      workflow_instance: @instance,
      actor:             actor,
      step_position:     step,
      channel:           :email_magic_link,
      responded_at:      Time.current,
      state:             state
    )
  rescue ActiveRecord::RecordInvalid => e
    @submit_error = e.message
  end
end

Then("the actor response channel should be {string}") do |channel|
  @last_magic_link_response.reload.channel.should == channel
end

Then("the second magic link submission should be rejected") do
  @submit_error.should_not be_nil
end
