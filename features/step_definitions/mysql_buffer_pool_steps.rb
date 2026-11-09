# frozen_string_literal: true

# Steps for features/misc/mysql_buffer_pool.feature. Pure: numbers in, plan out.

Given("a DB box with {int} MB RAM, {int} MB reserved for other services and mysqld resident at {int} MB") do |ram, reserved, rss|
  @mbp_box = { total_bytes: ram * MysqlBufferPool::MB, reserved_bytes: reserved * MysqlBufferPool::MB,
               mysqld_rss_bytes: rss * MysqlBufferPool::MB }
end

Given("its buffer pool is {int} MB in {int} MB units with a {int} MB dataset") do |pool, unit, dataset|
  @mbp_box.merge!(current_pool_bytes: pool * MysqlBufferPool::MB, unit_bytes: unit * MysqlBufferPool::MB,
                  dataset_bytes: dataset * MysqlBufferPool::MB)
end

When("the buffer pool is planned") do
  @mbp_plan = MysqlBufferPool.plan(**@mbp_box)
end

Then("the buffer pool plan is {string} to {int} MB") do |status, target|
  expect(@mbp_plan[:status]).to eq(status.to_sym), @mbp_plan[:reason]
  expect(@mbp_plan[:target]).to eq(target * MysqlBufferPool::MB)
end

Then("the buffer pool plan is {string}") do |status|
  expect(@mbp_plan[:status]).to eq(status.to_sym), @mbp_plan[:reason]
end

Then("the buffer pool plan is {string} mentioning {string}") do |status, text|
  expect(@mbp_plan[:status]).to eq(status.to_sym)
  expect(@mbp_plan[:reason]).to include(text)
end

Then("the room is {int} MB") do |room|
  expect(@mbp_plan[:room]).to eq(room * MysqlBufferPool::MB)
end

When("the memory reserved for {string} with an Elasticsearch cap of {int} MB and Redis maxmemory of {int} MB is worked out") do |containers, es_cap, redis_max|
  @mbp_reserved = MysqlBufferPool.reserved(containers: containers.split(","), es_cap_bytes: es_cap * MysqlBufferPool::MB,
                                           redis_maxmemory_bytes: redis_max * MysqlBufferPool::MB)
end

Then("the reservation is refused mentioning {string}") do |text|
  expect(@mbp_reserved[:refusal]).to include(text)
end

Then("{int} MB is reserved") do |mb|
  expect(@mbp_reserved).to eq(bytes: mb * MysqlBufferPool::MB)
end

# Built in Ruby rather than in the feature: Gherkin's own unescaping of \" and \\ would muddle it
MBP_AWKWARD_PASSWORD = %q(p#a;s "w\d)

When("the client option file is written for a password with a hash, a semicolon, a space, a double quote and a backslash") do
  @mbp_cnf = MysqlBufferPool.client_cnf(user: "root", password: MBP_AWKWARD_PASSWORD, host: "10.0.3.138")
end

Then("reading the option file back gives the same password") do
  # The way mysql reads a double-quoted option value: strip the quotes, then undo \" and \\
  raw = @mbp_cnf.lines.find { |l| l.start_with?("password=") }.chomp.delete_prefix("password=")
  expect(raw).to start_with('"')
  expect(raw).to end_with('"')
  read = raw[1..-2].gsub(/\\(["\\])/, '\1')
  expect(read).to eq(MBP_AWKWARD_PASSWORD)
end

When("the buffer pool task is asked for {string}") do |env|
  @mbp_allowed = MysqlBufferPool.env_allowed?(env)
end

Then("the buffer pool task is {string}") do |verdict|
  expect(@mbp_allowed).to eq(verdict == "allowed")
end
