# frozen_string_literal: true

# Sizing MySQL's InnoDB buffer pool on the DB boxes, and the pure decisions around resizing it —
# used by `rake "ops:mysql_buffer_pool[<env>]"` (lib/tasks/mysql_buffer_pool.rake) and
# features/misc/mysql_buffer_pool.feature.
#
# Why: every DB box ran MySQL's default 128 MB pool. On prod IN that is 0.5% of a 26 GB dataset,
# and up to 3.7% of reads went to disk (Grafana, 2026-11-09). Capping Elasticsearch and Redis
# (ops:data_box_limits) freed ~3.5 GB per data box; this hands MySQL its share.
#
# The rule (2026-11-09):
#   room = box RAM
#          - memory caps of the other services on the box (Elasticsearch cap, Redis maxmemory)
#          - 1.25 x what mysqld holds OUTSIDE the pool (connections, performance_schema, ...)
#          - 1.5 GB for the OS, backups (xtrabackup) and page cache
#   pool = min(room, 1.25 x the InnoDB dataset), in whole resize units (chunk x instances)
#   Never shrinks. Refused on a box with a service whose memory is not capped (no budget).
#
# Pure: no SSH, no MySQL. The rake task fetches the numbers and acts on the answers.
module MysqlBufferPool
  MB = 1_048_576
  OS_RESERVE_BYTES = 1536 * MB
  # Head-room on mysqld's non-pool memory (more connections, bigger sorts at a busy moment)
  NON_POOL_FACTOR = 1.25
  # A pool larger than the data has nothing to hold; 25% leaves room for growth
  DATASET_FACTOR = 1.25

  # Staging first, then production (decision 2026-11-09)
  ENVS = %w[staging.in production.in production.us].freeze

  # Containers whose memory we know how to budget for (ops:data_box_limits caps both)
  KNOWN_CONTAINERS = %w[elasticsearch redis-stack-server].freeze

  module_function

  def env_allowed?(env_name)
    ENVS.include?(env_name.to_s)
  end

  # The probe's "key: value" lines -> hash of strings
  def parse_probe(text)
    text.to_s.lines.filter_map { |l| l.chomp.split(": ", 2) if l.include?(": ") }.to_h
  end

  # Memory reserved for the other services on the box, or a refusal when one is unbounded.
  # es_cap_bytes: the elasticsearch container's memory cap (0 = none); redis_maxmemory: 0 = unlimited.
  def reserved(containers:, es_cap_bytes:, redis_maxmemory_bytes:)
    unknown = containers - KNOWN_CONTAINERS
    return { refusal: "unknown container(s) #{unknown.join(', ')} — cannot budget their memory" } if unknown.any?
    return { refusal: "elasticsearch has no memory cap — run ops:data_box_limits first" } if containers.include?("elasticsearch") && es_cap_bytes.zero?
    return { refusal: "Redis has no maxmemory — run ops:data_box_limits first" } if containers.include?("redis-stack-server") && redis_maxmemory_bytes.zero?

    bytes = 0
    bytes += es_cap_bytes if containers.include?("elasticsearch")
    bytes += redis_maxmemory_bytes if containers.include?("redis-stack-server")
    { bytes: bytes }
  end

  # The target pool and the working behind it.
  # unit_bytes: innodb_buffer_pool_chunk_size x innodb_buffer_pool_instances (MySQL rounds to it).
  # Returns { status: :grow / :unchanged / :refused, target:, room:, dataset_cap:, non_pool:, reason: }.
  def plan(total_bytes:, reserved_bytes:, mysqld_rss_bytes:, current_pool_bytes:, dataset_bytes:, unit_bytes:)
    # What mysqld holds besides the pool (never negative: RSS can trail a just-grown pool)
    non_pool = [mysqld_rss_bytes - current_pool_bytes, 0].max
    room = total_bytes - reserved_bytes - (NON_POOL_FACTOR * non_pool).ceil - OS_RESERVE_BYTES
    room_units = room.positive? ? (room / unit_bytes) * unit_bytes : 0
    dataset_cap = ((DATASET_FACTOR * dataset_bytes) / unit_bytes).ceil * unit_bytes
    dataset_cap = unit_bytes if dataset_cap < unit_bytes
    target = [room_units, dataset_cap].min
    base = { target: target, room: room, dataset_cap: dataset_cap, non_pool: non_pool }

    # The box is already past its budget: growing would invite the OOM killer, which picks mysqld
    return base.merge(status: :refused, reason: "no room: the budget leaves #{mb(room)} for the pool, below the current #{mb(current_pool_bytes)}") if room_units < current_pool_bytes
    # Never shrink, and nothing to do when already there
    return base.merge(status: :unchanged, reason: "pool already #{mb(current_pool_bytes)} (target #{mb(target)})") if target <= current_pool_bytes

    base.merge(status: :grow)
  end

  # The read-miss rate: buffer pool reads that went to disk, as a % of all logical reads
  def miss_percent(reads:, requests:)
    return 0.0 if requests.to_i.zero?

    (100.0 * reads.to_i / requests.to_i).round(3)
  end

  # A mysql client option file. Values are double-quoted, so a password with #, ; or spaces is
  # read whole (an unquoted # starts a comment); \ and " are escaped.
  def client_cnf(user:, password:, host:)
    quote = ->(v) { %("#{v.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}") }
    "[client]\nuser=#{quote.call(user)}\npassword=#{quote.call(password)}\nhost=#{quote.call(host)}\n"
  end

  def mb(bytes)
    "#{(bytes / MB.to_f).round} MB"
  end
end
