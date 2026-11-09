# frozen_string_literal: true

# Steps for features/misc/replica_read_only.feature. Pure guard plus a read of the two DR files.

Given("a replica {string} replicating from {string} with IO {string} and SQL {string}") do |host, source, io, sql|
  @rro_host = host
  @rro_status = { "Source_Host" => source, "Replica_IO_Running" => io, "Replica_SQL_Running" => sql }
end

Given("a box {string} with no replication") do |host|
  @rro_host = host
  @rro_status = {}
end

When("making it read-only is planned with primary {string}, read_only {string} and super_read_only {string}") do |primary, ro, sro|
  @rro_plan = ReplicaReadOnly.plan(replica_host: @rro_host, primary_host: primary, status: @rro_status,
                                   read_only: ro, super_read_only: sro)
end

Then("the read-only plan is {string}") do |status|
  expect(@rro_plan[:status]).to eq(status.to_sym), @rro_plan[:reason]
end

Then("the read-only plan is {string} mentioning {string}") do |status, text|
  expect(@rro_plan[:status]).to eq(status.to_sym)
  expect(@rro_plan[:reason]).to include(text)
end

When("the replica status text is {string}") do |text|
  @rro_parsed = ReplicaReadOnly.parse_replica_status(text.gsub('\n', "\n"))
end

Then("the parsed Source_Host is {string} and there is no {string} field") do |host, field|
  expect(@rro_parsed["Source_Host"]).to eq(host)
  expect(@rro_parsed).not_to have_key(field)
end

Then("reset_replication sets {string} unless the replica is the primary") do |statement|
  source = Rails.root.join("lib/tasks/aws_utils.rb").read
  method = source[/def reset_replication.*?\n  end\n/m]
  expect(method).to include(statement)
  expect(method).to include("if destination_host == source_host")
end

Then("promote_replica runs {string}") do |statements|
  expect(Rails.root.join("lib/tasks/dr_fix_db.rake").read).to include(statements)
end
