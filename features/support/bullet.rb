# Bullet needs explicit request boundaries in Cucumber — without these hooks
# it never activates and log/bullet.log stays empty.
Before do |scenario|
  Bullet.start_request if Bullet.enable?
end

After do |scenario|
  Bullet.end_request if Bullet.enable?
end
