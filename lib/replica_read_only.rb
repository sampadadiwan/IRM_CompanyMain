# frozen_string_literal: true

# Making the MySQL replica read-only, and the pure decisions around it — used by
# `rake "ops:replica_read_only[<env>]"` (lib/tasks/replica_read_only.rake) and
# features/misc/replica_read_only.feature.
#
# Why: the prod US replica ran with read_only = 0 and super_read_only = 0 (found 2026-11-09). It
# accepted writes, so one stray write (a console session, a mis-pointed script — and the app logs in
# as root, which read_only alone does NOT stop) would make it silently drift from the primary, and
# a later promotion would serve that drifted data. super_read_only = ON refuses writes from every
# client, root included; the replication threads still apply the primary's changes.
#
# Where else this lives (so it stays consistent):
# - AwsUtils#reset_replication turns it ON when it (re)connects a replica
# - dr:fix:promote_replica turns it OFF when the replica becomes the primary — without that a
#   promoted replica would refuse every write and the app would be down mid-recovery
#
# Pure: no SSH, no MySQL.
module ReplicaReadOnly
  # Staging's "replica" is its primary, so it is never a candidate (refused by replica == primary)
  ENVS = %w[staging.in production.in production.us].freeze

  module_function

  def env_allowed?(env_name)
    ENVS.include?(env_name.to_s)
  end

  # `SHOW REPLICA STATUS\G` (with field names) -> { "Source_Host" => "10.0.3.214", ... }
  def parse_replica_status(text)
    text.to_s.lines.filter_map do |line|
      key, value = line.strip.split(": ", 2)
      [key, value.to_s.strip] if key&.match?(/\A[A-Z][A-Za-z_]+\z/) && line.include?(":")
    end.to_h
  end

  # May this host be made read-only? It must be the replica (never the primary) and it must be
  # replicating FROM the primary — a box with no replication is not a replica, whatever the
  # credentials call it. Returns { status: :apply / :unchanged / :refused, reason: }.
  def plan(replica_host:, primary_host:, status:, read_only:, super_read_only:)
    return { status: :refused, reason: "no separate replica (DB_HOST_REPLICA is the primary) — nothing to make read-only" } if replica_host.to_s.empty? || replica_host == primary_host
    return { status: :refused, reason: "#{replica_host} is not replicating (no SHOW REPLICA STATUS) — refusing to make a non-replica read-only" } if status.empty?
    return { status: :refused, reason: "#{replica_host} replicates from #{status['Source_Host']}, not the primary #{primary_host}" } if status["Source_Host"] != primary_host
    return { status: :refused, reason: "replication is not healthy (IO #{status['Replica_IO_Running']}, SQL #{status['Replica_SQL_Running']}) — fix it first" } unless status["Replica_IO_Running"] == "Yes" && status["Replica_SQL_Running"] == "Yes"
    return { status: :unchanged, reason: "already read_only = 1, super_read_only = 1" } if read_only.to_s == "1" && super_read_only.to_s == "1"

    { status: :apply, reason: "read_only #{read_only} -> 1, super_read_only #{super_read_only} -> 1" }
  end
end
