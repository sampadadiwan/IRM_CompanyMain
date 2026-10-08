# The capital call and capital distribution journeys' "Review email" step is now "Review custom
# notification": the step reviews the record's custom notification (its own override, else the fund's
# default) and links to it, or to the form that creates one.
#
# Renames it in three places, only where it still carries the seeded name (a name an admin chose is kept):
#   - workflow_steps            — the templates, so new journeys get the new name
#   - workflow_instances.template_snapshot — journeys already running copied their steps at launch and
#                                 render names from that copy, so the template rename alone never reaches them
#   - workflow_instances.step_results      — the cached evaluation, which also carries each step's name
# Data only, no schema change. Raw SQL / JSON, independent of the models.
class RenameReviewEmailSteps < ActiveRecord::Migration[8.1]
  CHECK_KEYS = %w[capital_call.review_email capital_distribution.review_email].freeze
  WORKFLOWABLE_TYPES = %w[CapitalCall CapitalDistribution].freeze

  def up
    rename("Review email", "Review custom notification")
  end

  def down
    rename("Review custom notification", "Review email")
  end

  private

  def rename(from, to)
    rename_template_steps(from, to)
    rename_instance_copies(from, to)
  end

  # One UPDATE over the templates' steps
  def rename_template_steps(from, to)
    execute(<<~SQL.squish)
      UPDATE workflow_steps SET name = #{quote(to)}, updated_at = #{quote(Time.current)}
      WHERE check_key IN (#{CHECK_KEYS.map { |k| quote(k) }.join(', ')}) AND name = #{quote(from)}
    SQL
  end

  # Each call / distribution instance's snapshot and cached results, in id batches (a few thousand
  # rows at most; JSON is edited in Ruby so this runs the same on MySQL and the SQLite test database)
  def rename_instance_copies(from, to)
    last_id = 0
    loop do
      rows = select_rows(<<~SQL.squish)
        SELECT id, template_snapshot, step_results FROM workflow_instances
        WHERE workflowable_type IN (#{WORKFLOWABLE_TYPES.map { |t| quote(t) }.join(', ')}) AND id > #{last_id.to_i}
        ORDER BY id LIMIT 500
      SQL
      break if rows.empty?

      rows.each { |id, snapshot, results| rename_in_instance(id, parse(snapshot), results && parse(results), from, to) }
      last_id = rows.last.first
    end
  end

  def rename_in_instance(id, snapshot, results, from, to)
    # Positions of this check's steps that still carry the old name
    steps = Array(snapshot["steps"]).select { |s| CHECK_KEYS.include?(s["check_key"]) && s["name"] == from }
    return if steps.empty?

    # The snapshot step, then its cached result (an instance never evaluated has none: NULL stays NULL)
    steps.each do |s|
      s["name"] = to
      cached = results&.dig(s["position"].to_s)
      cached["name"] = to if cached.is_a?(Hash) && cached["name"] == from
    end

    execute(<<~SQL.squish)
      UPDATE workflow_instances SET template_snapshot = #{quote(snapshot.to_json)}, step_results = #{results ? quote(results.to_json) : 'NULL'}
      WHERE id = #{id.to_i}
    SQL
  end

  def parse(json)
    json.is_a?(Hash) ? json : JSON.parse(json.presence || "{}")
  end

  def quote(value)
    connection.quote(value)
  end
end
