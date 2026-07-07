# Shared helpers for workflow-template seed rake tasks (lib/tasks/workflow_seeds.rake,
# lib/tasks/investor_workflow_seeds.rake). Both seed WorkflowTemplate + WorkflowStep rows for
# a given entity with identical idempotency/logging/actor-selection conventions — factored out
# here so the two rake files can't silently drift out of sync.
module WorkflowSeedHelpers
  # Loads the entity and picks its first two employees as default actors (falling back to the
  # same employee twice if only one exists), enabling enable_workflow_templates along the way.
  # Aborts with a message on failure — same as each rake task's own entity_id-blank guard.
  def self.load_entity_and_actors(entity_id)
    entity = Entity.find_by(id: entity_id) || abort("Entity #{entity_id} not found")
    entity.permissions.set(:enable_workflow_templates)
    entity.save

    employees = entity.employees.to_a
    abort "No employees found for entity #{entity_id}" if employees.empty?

    [entity, employees[0], employees[1] || employees[0]]
  end

  # Returns a logger lambda that prefixes every message with "[prefix]".
  def self.logger_for(prefix)
    ->(msg) { puts "[#{prefix}] #{msg}" }
  end

  # Find-or-skip a template by (entity, name); yields the new template to a block that adds
  # steps, but only when the template was actually just created (not on an existing find).
  # Returns [template, created?] so the caller can track its own created/skipped counters.
  def self.create_template(entity, name, attrs, log:, &block)
    existing = WorkflowTemplate.find_by(entity: entity, name: name)
    if existing
      log.call("SKIP  #{name} (id=#{existing.id}) — already exists")
      return [existing, false]
    end

    template = WorkflowTemplate.create!(attrs.merge(entity: entity, name: name))
    log.call("CREATE #{name} (id=#{template.id})")
    block.call(template)
    [template, true]
  end

  # Adds a step with named actors to a template.
  def self.add_step(template, pos, step_name, actors, step_attrs, log:)
    step = template.workflow_steps.create!(
      { position: pos, name: step_name }.merge(step_attrs)
    )
    actors.each { |u| step.workflow_step_actors.create!(user: u) }
    log.call("         Step #{pos}: #{step_name} — actors: #{actors.map(&:email).join(', ')}")
  end
end
