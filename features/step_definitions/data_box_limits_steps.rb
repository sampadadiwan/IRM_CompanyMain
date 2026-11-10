# frozen_string_literal: true

# Steps for features/misc/data_box_limits.feature. Pure: numbers, docker-inspect-shaped JSON,
# crontab text and the repo's start script in memory.

DATA_BOX_IMAGE_ENV = ["PATH=/usr/share/elasticsearch/bin:/usr/bin", "ELASTIC_CONTAINER=true"].freeze

# A `docker inspect` / `docker image inspect` pair for an Elasticsearch container
def data_box_es_state(image:, settings:, memory_mb: 0, auto_remove: true, restart: "no", volume: nil)
  mounts = volume ? [{ "Type" => "volume", "Name" => volume, "Destination" => DataBoxLimits::ES_DATA_DIR }] : []
  container = [{ "Config" => { "Image" => image, "Env" => settings + DATA_BOX_IMAGE_ENV },
                 "HostConfig" => { "Memory" => memory_mb * DataBoxLimits::MB, "AutoRemove" => auto_remove,
                                   "RestartPolicy" => { "Name" => restart } },
                 "Mounts" => mounts }]
  DataBoxLimits.es_container_state(container.to_json, [{ "Config" => { "Env" => DATA_BOX_IMAGE_ENV } }].to_json)
end

# --- Sizing ----------------------------------------------------------------------------------

When("the data box limits are sized for an Elasticsearch old-generation peak of {float} MB and a Redis peak of {float} MB") do |old_mb, redis_mb|
  @data_box_heap = DataBoxLimits.es_heap_mb((old_mb * DataBoxLimits::MB).to_i)
  @data_box_cap = DataBoxLimits.es_container_mb(@data_box_heap)
  @data_box_redis = DataBoxLimits.redis_maxmemory_bytes((redis_mb * DataBoxLimits::MB).to_i)
end

Then("the Elasticsearch heap is {int} MB with a container cap of {int} MB") do |heap, cap|
  expect(@data_box_heap).to eq(heap)
  expect(@data_box_cap).to eq(cap)
end

Then("the Redis maxmemory is {int} MB") do |mb|
  expect(@data_box_redis).to eq(mb * DataBoxLimits::MB)
end

# --- Elasticsearch container -----------------------------------------------------------------

Given("the live Elasticsearch container runs {string} with --rm, no memory cap, no volume and settings {string}") do |image, settings|
  @data_box_es = data_box_es_state(image: image, settings: settings.split(","))
end

Given("the live Elasticsearch container already matches a 512 MB heap, a 1536 MB cap, the volume and unless-stopped") do
  @data_box_es = data_box_es_state(image: DataBoxLimits::ES_IMAGE, memory_mb: 1536, auto_remove: false, restart: "unless-stopped",
                                   volume: DataBoxLimits::ES_VOLUME,
                                   settings: ["ES_JAVA_OPTS=-Xms512m -Xmx512m", "discovery.type=single-node", "xpack.security.enabled=false"])
end

When("its drift from a {int} MB heap and a {int} MB cap is checked") do |heap, cap|
  @data_box_drift = DataBoxLimits.es_drift(@data_box_es, heap_mb: heap, container_mb: cap)
end

Then("the Elasticsearch drift mentions {string}, {string}, {string} and {string}") do |*texts|
  texts.each { |t| expect(@data_box_drift.join(" | ")).to include(t) }
end

Then("there is no Elasticsearch drift") do
  expect(@data_box_drift).to be_empty
end

Then("re-creating the Elasticsearch container is allowed") do
  expect(DataBoxLimits.es_recreate_refusal(@data_box_es)).to be_nil
end

Then("re-creating the Elasticsearch container is refused mentioning {string}") do |text|
  expect(DataBoxLimits.es_recreate_refusal(@data_box_es)).to include(text)
end

Then("an existing elasticsearch-data volume {string} is {string}") do |exists, verdict|
  stale = DataBoxLimits.stale_volume?(@data_box_es, volume_exists: exists == "yes")
  expect(stale).to eq(verdict == "moved aside")
end

# --- Crontab ---------------------------------------------------------------------------------

Given("a data box crontab:") do |text|
  @data_box_crontab = "#{text}\n"
end

When("the data box crontab is planned") do
  @data_box_cron = DataBoxLimits.crontab_plan(@data_box_crontab)
end

Then("the data box crontab change is {string} removing {int} lines") do |status, count|
  expect(@data_box_cron[:status]).to eq(status.to_sym)
  expect(@data_box_cron[:removed].size).to eq(count)
end

Then("the data box crontab boots through the start script") do
  lines = @data_box_cron[:text].lines.map(&:chomp)
  expect(lines).to include(DataBoxLimits::SCRIPT_CRON_LINE)
  expect(lines.grep(DataBoxLimits::RAW_CONTAINER_LINE)).to be_empty
end

Then("the data box crontab still has {string}") do |line|
  expect(@data_box_cron[:text].lines.map(&:chomp)).to include(line)
end

# --- Readings --------------------------------------------------------------------------------

When("Redis INFO memory reports used {int}, peak {int}, maxmemory {int} and policy {string}") do |used, peak, max, policy|
  # redis-cli INFO answers with CRLF line endings
  text = "# Memory\r\nused_memory:#{used}\r\nused_memory_peak:#{peak}\r\nmaxmemory:#{max}\r\nmaxmemory_policy:#{policy}\r\n"
  @data_box_redis_info = DataBoxLimits.parse_redis_info(text)
end

Then("the data box Redis reading is used {int}, peak {int}, maxmemory {int} and policy {string}") do |used, peak, max, policy|
  expect(@data_box_redis_info).to eq(used_memory: used, used_memory_peak: peak, maxmemory: max, maxmemory_policy: policy)
end

When("the Elasticsearch JVM stats are {string}") do |text|
  @data_box_jvm = DataBoxLimits.parse_es_jvm(text)
end

Then("there are no Elasticsearch JVM stats") do
  expect(@data_box_jvm).to be_nil
end

# --- Start script ----------------------------------------------------------------------------

When("I read the data box start script") do
  @data_box_script = Rails.root.join(DataBoxLimits::SCRIPT_REPO_PATH).read
end

Then("the data box start script sources {string}") do |path|
  expect(@data_box_script).to include(". #{path}")
end

Then("the data box start script starts Elasticsearch with {string}, {string} and {string}") do |*flags|
  flags.each { |f| expect(@data_box_script).to include(f) }
  # Not --rm: docker refuses --rm with --restart, and --rm would delete the container on stop
  es_run = @data_box_script[/\$DOCKER run -d \\\n\s+--name elasticsearch.*?elasticsearch:\S+/m]
  expect(es_run).to be_present
  expect(es_run).not_to include("--rm")
  expect(es_run).to include(DataBoxLimits::ES_IMAGE)
end

Then("the data box start script starts Redis with {string}") do |args|
  expect(@data_box_script).to include(args)
end

Then("the start script's floor values are the rule's floor") do
  # A fresh AMI / DR box (no limits file) must get exactly what the rule gives a near-idle box
  heap = DataBoxLimits.es_heap_mb(0)
  expect(@data_box_script).to include("ES_HEAP=#{heap}m")
  expect(@data_box_script).to include("ES_MEMORY=#{DataBoxLimits.es_container_mb(heap)}m")
  expect(@data_box_script).to include("REDIS_MAXMEMORY=#{DataBoxLimits.redis_maxmemory_bytes(0) / DataBoxLimits::MB}mb")
end

# --- Environments ----------------------------------------------------------------------------

When("the data box limits task is asked for {string}") do |env|
  @data_box_env_allowed = DataBoxLimits.env_allowed?(env)
end

Then("the data box limits task is {string}") do |verdict|
  expect(@data_box_env_allowed).to eq(verdict == "allowed")
end

# --- Which boxes -----------------------------------------------------------------------------

When("the boxes are chosen for data box {string}, replica {string} running {string}") do |data_box, replica, containers|
  @data_box_targets = DataBoxLimits.target_boxes(data_box: data_box, replica: replica, replica_containers: containers.split(","))
end

Then("the chosen boxes are {string}") do |expected|
  expect(@data_box_targets.map { |t| "#{t[:host]} #{t[:status]}" }.join(", ")).to eq(expected)
end

When("the reindex is weighed for the {string} with drift {string} and data volume {string}") do |role_name, drift, volume|
  role = role_name == "data box" ? :data_box : :replica
  @data_box_reindex = DataBoxLimits.reindex_needed?(role: role, drift: drift.empty? ? [] : [drift], volume: volume.presence)
end

Then("the reindex is {string}") do |verdict|
  expect(@data_box_reindex).to eq(verdict == "needed")
end
