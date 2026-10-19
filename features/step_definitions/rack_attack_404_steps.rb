require 'rack/test'

# HTTP client that drives the FULL Rails middleware stack (Log404s +
# Rack::Attack included) for one simulated visitor. Capybara's playwright
# driver always originates from 127.0.0.1 — which is (deliberately)
# safelisted — so external clients are simulated by sending X-Forwarded-For,
# exactly the header nginx/the ALB appends for a real remote client.
#
# Each instance has its own Rack::Test session, i.e. its own cookie jar, so a
# scenario can interleave an anonymous scanner and a signed-in user on the
# same or different IPs.
class RackAttackClient
  include Rack::Test::Methods

  attr_reader :ip

  # ip: the simulated external client address; nil simulates loopback traffic
  # (health checks / monitoring) that carries no X-Forwarded-For at all.
  def initialize(ip)
    @ip = ip
  end

  def app
    Rails.application
  end

  def get_path(path)
    get(path, {}, request_env)
    last_response
  end

  # Signs in through the real Devise endpoint so the session cookie carries a
  # genuine warden.user.* key — the exact thing the middleware exemption
  # checks. Raises loudly on failure so scenarios can't silently run
  # "signed in" assertions as an anonymous user.
  def sign_in!(user)
    post('/users/sign_in', { user: { email: user.email, password: 'password' } }, request_env)
    unless last_response.status == 302
      raise "Devise sign-in failed for #{user.email}: HTTP #{last_response.status}"
    end
    last_response
  end

  # What a scanner does: attach a forged session cookie hoping to be treated
  # as logged in. It cannot decrypt, so the middleware must still count it.
  def spoof_session_cookie!
    session_key = Rails.application.config.session_options[:key]
    set_cookie("#{session_key}=totally-forged-session-value")
  end

  private

  def request_env
    env = {}
    env['HTTP_X_FORWARDED_FOR'] = ip if ip
    env
  end
end

Given('a visitor {string} browsing from IP {string}') do |name, ip|
  @rack_clients ||= {}
  @rack_clients[name] = RackAttackClient.new(ip)
end

Given('a visitor {string} with no forwarded IP') do |name|
  @rack_clients ||= {}
  @rack_clients[name] = RackAttackClient.new(nil)
end

Given('{string} carries a spoofed session cookie') do |name|
  @rack_clients[name].spoof_session_cookie!
end

Given('{string} signs in with valid credentials') do |name|
  # @user comes from the shared "there is a user ... for an entity" step.
  @rack_clients[name].sign_in!(@user)
end

# Lenient probe step for scanners: each probe must be a real 404 OR one of
# the escalations the defenses are allowed to answer with (403 once blocked,
# 429 once throttled). Anything else means the scenario isn't exercising the
# middleware it claims to.
When('{string} requests {int} different missing pages') do |name, count|
  client = @rack_clients[name]
  count.times do |i|
    response = client.get_path("/definitely-missing-#{name.parameterize}-#{i}-#{SecureRandom.hex(4)}")
    expect([404, 403, 429]).to include(response.status),
      "probe #{i + 1} for #{name} returned unexpected HTTP #{response.status}"
  end
end

# Strict probe step for visitors who must NEVER be escalated against
# (signed-in users, safelisted health checks): every probe must come back as
# a plain 404 — a single 403/429 here is exactly the lockout bug this
# feature exists to prevent.
When('{string} requests {int} different missing pages and each returns a plain 404') do |name, count|
  client = @rack_clients[name]
  count.times do |i|
    response = client.get_path("/definitely-missing-#{name.parameterize}-#{i}-#{SecureRandom.hex(4)}")
    expect(response.status).to eq(404),
      "probe #{i + 1} for #{name} should be an unpunished 404 but got HTTP #{response.status}"
  end
end

Then('{string} is blocked with {string} when visiting {string}') do |name, status_text, path|
  response = @rack_clients[name].get_path(path)
  expect(response.status).to eq(status_text.to_i),
    "expected #{name} to be blocked (#{status_text}) on #{path}, got HTTP #{response.status}"
end

# "Not blocked" deliberately accepts any NON-defensive outcome: anonymous
# visitors are legitimately redirected to sign-in (302) and signed-in users
# get 200 — only the scanner defenses (403 blocklist, 429 throttle) fail it.
Then('{string} is not blocked when visiting {string}') do |name, path|
  response = @rack_clients[name].get_path(path)
  expect([403, 429]).not_to include(response.status),
    "expected #{name} to reach #{path}, but the scanner defenses answered HTTP #{response.status}"
end

Then('{string} can load the sign-in page') do |name|
  response = @rack_clients[name].get_path('/users/sign_in')
  expect(response.status).to eq(200),
    "expected #{name} to reach the sign-in page, got HTTP #{response.status}"
end

Then('{string} can still browse the app normally') do |name|
  response = @rack_clients[name].get_path('/entities/dashboard')
  # 200 or an in-app redirect are both normal; 403/429 mean the defenses
  # wrongly caught a valid user, and a sign-in redirect means the session was
  # dropped.
  expect(response.status).to be_between(200, 399),
    "expected #{name} to browse normally, got HTTP #{response.status}"
  expect(response.headers['Location'].to_s).not_to include('/users/sign_in')
end

# Reads through Rack::Attack.cache.store, NOT Rails.cache: the two only
# happen to be the same object under the @rack_attack hook. @rack_attack_redis
# points the attack store at Redis while Rails.cache stays in memory, and
# production splits them too (Redis vs Solid Cache) — asserting on Rails.cache
# would quietly stop looking at the counter the middleware actually writes.
Then('no 404 strikes are recorded against IP {string}') do |ip|
  counter = Rack::Attack.cache.store.read("rack::attack:404:#{ip}", raw: true)
  expect(counter).to be_nil,
    "expected no 404 counter for #{ip}, found #{counter.inspect}"
end

Then('{string} receives {string} within {int} visits to {string}') do |name, status_text, attempts, path|
  expected = status_text.to_i
  statuses = []
  attempts.times do
    statuses << @rack_clients[name].get_path(path).status
    break if statuses.last == expected
  end
  expect(statuses.last).to eq(expected),
    "expected #{name} to hit HTTP #{expected} within #{attempts} visits, saw #{statuses.inspect}"
end

# Aligns the clock to a whole minute so every request in the scenario falls
# into one deterministic Rack::Attack throttle window (they are epoch-based
# 10-second buckets) and the 1-minute 404 counter cannot expire mid-scenario.
Given('the clock is frozen for predictable rate-limit windows') do
  travel_to(Time.current.change(sec: 0, usec: 0))
end

# '{int} minutes pass' is defined once, in mobile_api_steps.rb (a second copy makes Cucumber stop as ambiguous)
