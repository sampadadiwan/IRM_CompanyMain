# Backup tables made while validating allocation changes on a local copy of production — ae_snapshot_*
# (lib/tasks/allocation_snapshot.rake) and ff_snapshot_* (formula backups) — must never reach db/schema.rb.
# A dump that picked them up broke the SQLite test schema load: every snapshot table carries the same
# index name, and SQLite index names are database-wide.
ActiveRecord::SchemaDumper.ignore_tables += [/\Aae_snapshot_/, /\Aff_snapshot_/]
