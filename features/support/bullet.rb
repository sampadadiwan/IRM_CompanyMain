# Bullet needs explicit request boundaries in Cucumber — without these hooks
# it never activates and log/bullet.log stays empty. The gem is only loaded with BULLET=1 (see Gemfile).
Before do |scenario|
  Bullet.start_request if defined?(Bullet) && Bullet.enable?
end

After do |scenario|
  Bullet.end_request if defined?(Bullet) && Bullet.enable?
end
