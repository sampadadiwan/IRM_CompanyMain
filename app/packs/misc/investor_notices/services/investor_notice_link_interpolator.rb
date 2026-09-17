# Safely interpolates [user.xxx] variables into InvestorNoticeItem#link at
# render time, per viewer — e.g. `/entities/[user.entity.sub_domain]/dashboard`.
#
# Like InvestorNoticeCriteriaEvaluator, this never calls an arbitrary method
# on a live model and never uses eval — it only ever reads a real DB column
# (via read_attribute) and only ever traverses a small, explicit allow-list of
# belongs_to associations, starting from current_user.
#
# Two allow-lists gate what's reachable, deliberately narrower than "every
# column reachable from User": ALLOWED_COLUMNS (a *denylist* was considered
# and rejected — User alone has encrypted_password, otp_secret,
# reset_password_token, session_token... a denylist only has to miss one of
# those once to leak a credential into a URL) and ALLOWED_ASSOCIATIONS (never
# an arbitrary method call, only a known-safe belongs_to). Extend both
# explicitly to add a new variable — never widen the traversal mechanism
# itself.
class InvestorNoticeLinkInterpolator
  BRACKET = /\[([^\]]+)\]/

  ALLOWED_COLUMNS = {
    "User" => %w[id email first_name last_name phone curr_role],
    "Entity" => %w[id name sub_domain domain primary_email currency entity_type]
  }.freeze

  ALLOWED_ASSOCIATIONS = {
    "User" => %w[entity]
  }.freeze

  # @return [String, nil] the interpolated link, or nil if link is blank or
  #   any [user...] variable can't be resolved for this viewer. Callers
  #   should treat nil the same as a blank link — render plain text, no <a>,
  #   rather than link to a broken/partially-substituted URL.
  def self.resolve(link, user)
    return nil if link.blank?
    return link unless link.match?(BRACKET)

    link.gsub(BRACKET) do
      value = resolve_path(user, Regexp.last_match(1).strip.split("."))
      return nil if value.nil?

      value.to_s
    end
  rescue StandardError => e
    Rails.logger.warn("[InvestorNoticeLinkInterpolator] error=#{e.message}")
    nil
  end

  # Schema-only check (no live user needed) — used by InvestorNoticeItem's
  # save-time validation so an unsupported path is rejected immediately,
  # instead of silently rendering the item as plain text for every viewer
  # later.
  # @return [true, String] true if every [user...] path in link resolves
  #   against the allow-lists, else a description of the first bad one
  def self.validate(link)
    return true if link.blank?

    link.scan(BRACKET).each do |(path)|
      segments = path.strip.split(".")
      return "#{path.inspect} must start with \"user.\"" unless segments.first == "user"
      return "#{path.inspect} is not a supported variable" unless path_valid?(User, segments[1..])
    end
    true
  end

  # segments here excludes the leading "user" — e.g. ["entity", "sub_domain"]
  def self.path_valid?(klass, segments)
    return false if segments.empty?

    segments.each_with_index do |segment, idx|
      if idx == segments.size - 1
        return (ALLOWED_COLUMNS[klass.name] || []).include?(segment)
      elsif (ALLOWED_ASSOCIATIONS[klass.name] || []).include?(segment)
        assoc = klass.reflect_on_association(segment)
        return false unless assoc&.macro == :belongs_to

        klass = assoc.klass
      else
        return false
      end
    end
    false
  end
  private_class_method :path_valid?

  # segments here includes the leading "user" — e.g. ["user", "entity", "sub_domain"]
  def self.resolve_path(user, segments)
    segments = segments.dup
    return nil unless segments.shift == "user"

    obj = user
    segments.each_with_index do |segment, idx|
      return nil if obj.nil?

      klass_name = obj.class.name
      if idx == segments.size - 1
        return (ALLOWED_COLUMNS[klass_name] || []).include?(segment) ? obj.read_attribute(segment) : nil
      elsif (ALLOWED_ASSOCIATIONS[klass_name] || []).include?(segment)
        obj = obj.public_send(segment)
      else
        return nil
      end
    end
    nil
  end
  private_class_method :resolve_path
end
