# Only enable WebMock for scenarios tagged @sync-http

Around('@sync-http') do |scenario, block|
  require 'webmock/cucumber'  # loads WebMock + adds helpers
  WebMock.enable!
  WebMock.disable_net_connect!(allow_localhost: true)

  block.call
ensure
  WebMock.reset!
  WebMock.allow_net_connect!
  WebMock.disable!
end
