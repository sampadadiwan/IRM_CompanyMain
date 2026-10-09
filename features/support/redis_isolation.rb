# Every cucumber process gets a Redis db of its own and empties it before each
# scenario, so test traffic never reaches the dev databases (0 = dev Sidekiq,
# 1 = dev ActionCable) and one run never sees another's keys.
#
# config/environments/test.rb sets the default REDIS_URL:
#   pcuc workers (TEST_ENV_NUMBER 1..8) -> dbs 2..9, fixed and unique, used as is.
#   anything else                      -> reconsidered here: an ad-hoc run
#     (TEST_ENV_NUMBER=$RANDOM) RESERVES the first free db in 10..15 instead of
#     deriving one from the number, so two concurrent ad-hoc runs can never land
#     on the same db and flush each other's keys mid-scenario.
#
# The reservation is a key inside the reserved db itself, renewed on every scenario.
# A run that dies without cleaning up frees its db once the key expires.
module RedisIsolation
  AD_HOC_DBS = (10..15)
  LOCK_KEY = 'cucumber_redis_db_lock'.freeze
  # Must outlast the longest single scenario: the lock is only renewed between scenarios.
  LOCK_TTL = 15.minutes.to_i

  module_function

  def lock_owner
    "#{Socket.gethostname}:#{Process.pid}"
  end

  # Returns the db to reserve for an ad-hoc run, or nil when REDIS_URL is used as is.
  def claim_db
    # An explicit REDIS_URL is never second-guessed (host or db).
    return nil unless ENV['REDIS_URL_FROM_TEST_ENV']

    # A pcuc worker number keeps test.rb's fixed db.
    configured_db = RedisClient.config(url: ENV.fetch('REDIS_URL')).db
    return nil unless AD_HOC_DBS.cover?(configured_db)

    # Take the first db whose lock key we can create (SET NX); the rest are in use.
    AD_HOC_DBS.each do |db|
      client = RedisClient.new(url: "redis://localhost:6379/#{db}")
      claimed = client.call('SET', LOCK_KEY, lock_owner, 'NX', 'EX', LOCK_TTL)
      client.close
      return db if claimed
    end

    raise "All ad-hoc cucumber Redis dbs (#{AD_HOC_DBS}) are reserved by other runs. " \
          "Wait for one to finish (a dead run's reservation expires in #{LOCK_TTL / 60} minutes), " \
          "or set REDIS_URL to a free db."
  end

  # Empties the db and re-writes our reservation in one MULTI, so no other run can
  # grab the db in the gap between the flush and the re-lock.
  # Only a run that reserved its db (relock: true) writes the lock back.
  def flush(conn, relock:)
    conn.multi do |tx|
      tx.call('FLUSHDB')
      tx.call('SET', LOCK_KEY, lock_owner, 'EX', LOCK_TTL) if relock
    end
  end

  # Gives the db back on exit, but only if the reservation is still ours.
  def release(db)
    client = RedisClient.new(url: "redis://localhost:6379/#{db}")
    client.call('EVAL', "if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('DEL', KEYS[1]) end", 1, LOCK_KEY, lock_owner)
    client.close
  rescue RedisClient::Error
    nil # Redis gone at exit: the key expires on its own.
  end
end

# Reserve the db while support files load, before any scenario has touched Redis,
# and point every consumer at it: REDIS_URL for rack_attack / SectionContentCache,
# and Sidekiq's client config (read when its pool is first built, which is lazy).
claimed_db = RedisIsolation.claim_db
if claimed_db
  ENV['REDIS_URL'] = "redis://localhost:6379/#{claimed_db}"
  Sidekiq.default_configuration.redis = { url: ENV.fetch('REDIS_URL') }
  at_exit { RedisIsolation.release(claimed_db) }
end
REDIS_ISOLATION_DB = RedisClient.config(url: ENV.fetch('REDIS_URL')).db

Before do
  # Read the db the Sidekiq client is actually connected to, not the env var,
  # so the guards check what the flush would really hit.
  redis_db = Sidekiq.redis { |conn| conn.config.db }

  # Never flush the dev databases (0 = dev Sidekiq queues, 1 = dev ActionCable),
  # e.g. if someone runs the suite with REDIS_URL=redis://localhost:6379.
  raise "Refusing to flush Redis db #{redis_db}: it belongs to development. Point REDIS_URL at db 2..15." if redis_db < 2

  # Sidekiq memoises its pool, so if something built it before this file ran, it still
  # points at test.rb's default db, which may be another run's reservation.
  raise "Sidekiq is on Redis db #{redis_db}, not the reserved db #{REDIS_ISOLATION_DB}: its pool was built too early." if redis_db != REDIS_ISOLATION_DB

  Sidekiq.redis { |conn| RedisIsolation.flush(conn, relock: !claimed_db.nil?) }
end
