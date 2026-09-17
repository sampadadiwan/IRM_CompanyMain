# Rate limits for two-factor SMS sends.
#
# See docs/technical/twilio_sms_otp_design.md section 9.
#
# WHY THIS IS NOT OPTIONAL SCOPE
#
# SMS costs real money per message, which makes the send path a direct financial
# liability rather than a nuisance. The standard attack is SMS pumping (toll fraud):
# an attacker points accounts at premium-rate numbers they control and takes a cut of
# the termination fee. Victims have absorbed six-figure bills in days.
#
# We chose Twilio's Messages API over Verify, which means we do not inherit Twilio's
# fraud controls — this class is the price of that decision.
#
# WHY THE PER-NUMBER LIMIT IS THE IMPORTANT ONE
#
# Per-user limits assume the attacker is constrained by accounts. They are not. The
# payout is per message delivered to THEIR number, so the incentive is to point as many
# accounts as they can obtain at one number. Ten accounts under a 10/day per-user cap is
# 100 messages a day to a single premium number, and every one of those accounts looks
# perfectly well-behaved in isolation. Only a key on the destination sees the pattern.
#
# The per-IP limit lives in Rack::Attack instead — a background job has no request.
class OtpSmsRateLimiter
  # Short windows, counted in Rails.cache.
  #
  # The 60-second window deserves a note: it must NOT block a user's first legitimate
  # resend. SMS can take 30+ seconds to arrive and a TOTP code is only valid for 30-60
  # seconds, so a user whose code lands late needs another one at around the 60-second
  # mark. The controller's session cooldown is derived from this value for that reason.
  NUMBER_LIMITS = {
    60.seconds => 1, # one code in flight at a time
    1.hour => 5,     # a bad signal day: several attempts, a couple of lost messages
    24.hours => 10   # matches the per-user cap
  }.freeze

  # The long window is counted in the DATABASE, not the cache.
  #
  # config/solid_cache.yml sets max_age to 1 week and max_size to 256MB, and SolidCache
  # trims by age and size regardless of an entry's own expires_in. A 30-day counter in
  # the cache would therefore reset weekly — or sooner under size pressure — and quietly
  # enforce ~50/week while claiming to enforce 50/30 days. Since this window exists
  # precisely to catch slow, patient pumping that stays under every shorter limit, a
  # counter that silently resets is worse than none.
  #
  # otp_deliveries has an index on [to_number_digest, created_at] for exactly this query.
  LONG_WINDOW = 30.days
  LONG_WINDOW_LIMIT = 50

  # Per user. Narrower than the per-number limits because one user legitimately needs
  # far fewer codes than a shared handset might.
  USER_LIMITS = {
    24.hours => 10
  }.freeze

  # The shortest per-number window. The controller reads this so its session cooldown
  # cannot drift below the durable limit — if it did, a resend would pass the controller,
  # be refused here, and the user would be told a code was sent that never was.
  def self.min_number_window
    NUMBER_LIMITS.keys.min
  end

  Result = Struct.new(:allowed, :scope, keyword_init: true) do
    def allowed? = allowed
  end

  # @param user [User]
  def initialize(user)
    @user = user
  end

  # Records the attempt, then reports whether it was within every limit.
  #
  # INCREMENT-THEN-COMPARE, deliberately. The obvious shape — check every window, then
  # increment them — is check-then-act: two concurrent sends both read a count under the
  # limit and both proceed, so a double-click that lands before the button disables, or
  # an ActiveJob retry racing the original, slips past a "1 per 60 seconds" cap. For the
  # one control that caps real spend, that race is worth closing.
  #
  # Counts ATTEMPTS, not successes — a number that reliably errors must not become free
  # to hammer, and errored sends still cost us (some carriers bill rejections, and every
  # attempt is a queue slot and an API call).
  #
  # @return [Result] allowed?, plus which scope tripped (for logging, never for the user)
  def check_and_record
    digest = @user.sms_number_digest
    # No dialable number means nothing to rate limit — the caller refuses for its own
    # reasons before reaching Twilio.
    return Result.new(allowed: true, scope: nil) if digest.blank?

    # The database window is read-only here; the OtpDelivery row the caller writes for
    # this attempt is what increments it.
    return Result.new(allowed: false, scope: "number:#{LONG_WINDOW.inspect}") if OtpDelivery.attempts_for_number(digest, LONG_WINDOW) >= LONG_WINDOW_LIMIT

    exceeded = nil
    NUMBER_LIMITS.each do |window, limit|
      count = bump(number_key(digest, window), window)
      exceeded ||= "number:#{window.inspect}" if count > limit
    end
    USER_LIMITS.each do |window, limit|
      count = bump(user_key(window), window)
      exceeded ||= "user:#{window.inspect}" if count > limit
    end

    Result.new(allowed: exceeded.nil?, scope: exceeded)
  end

  # Gives back the shortest-window slot after a TRANSIENT failure (a timeout or a
  # connection reset), so the ActiveJob retry is not guaranteed to be refused by the
  # very limit this attempt consumed.
  #
  # Only the 60-second window is released. The longer windows keep counting the attempt,
  # because an endlessly retrying send is still traffic worth capping.
  #
  # Not released for permanent failures: those are not retried, and a number that
  # reliably errors must keep accruing attempts.
  def release_short_window
    digest = @user.sms_number_digest
    return if digest.blank?

    key = number_key(digest, self.class.min_number_window)
    Rails.cache.decrement(key) if Rails.cache.read(key).to_i.positive?
  end

  private

  # The cache key is derived material rather than the number itself, so a cache dump
  # does not become a phone-number list.
  #
  # The digest is of the NORMALISED number (see SmsDeliverable#sms_number_digest) — if
  # it were of the raw stored string, "(415) 555-0134" and "+14155550134" would be
  # different keys and this whole limiter would be defeated by a reformat.
  def number_key(digest, window)
    "otp_sms:number:#{digest}:#{window.to_i}"
  end

  def user_key(window)
    "otp_sms:user:#{@user.id}:#{window.to_i}"
  end

  # Atomic increment returning the new count.
  #
  # Rails.cache#increment is atomic on the Redis and SolidCache stores; a read-then-write
  # is not, and would let two concurrent first sends each write 1 so the counter reads 1
  # after two messages went out.
  #
  # Deliberately NOT the session — the existing WhatsApp cooldown is stored in
  # session[:otp_whatsapp_sent_at], which is a value in the caller's own cookie and
  # resets when they clear it. That is tolerable for WhatsApp; for SMS it would be a
  # funded attack surface.
  def bump(key, window)
    # expires_in applies when increment creates the key, so the window is set atomically
    # with the first count rather than in a separate write that could be lost in a race.
    Rails.cache.increment(key, 1, expires_in: window) || 1
  end
end
