# Only enable WebMock for scenarios tagged @sync-http or @zoho-http

Around('@sync-http or @zoho-http') do |_scenario, block|
  require 'webmock/cucumber' # loads WebMock + adds helpers
  WebMock.enable!
  WebMock.disable_net_connect!(allow_localhost: true)

  block.call
ensure
  WebMock.reset!
  WebMock.allow_net_connect!
  WebMock.disable!
end
