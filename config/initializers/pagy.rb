# frozen_string_literal: true

# Pagy initializer file
# Customize Pagy to fit your needs.
# See https://ddnexus.github.io/pagy/docs/setup
require 'pagy' # Ensure Pagy core is loaded first
require 'pagy/extras/bootstrap' # Ensure Bootstrap extra is loaded
require 'pagy/extras/countless'
require 'pagy/extras/pagy' # ← adds pagy_prev_a / pagy_next_a / pagy_prev_link …
# require 'pagy/extras/keyset'

# Pagy Variables
# See https://ddnexus.github.io/pagy/docs/setup#variables
Pagy::DEFAULT[:limit] = 10 # default number of items per page
require 'pagy/extras/size' # Provide legacy support of old navbars like the above
Pagy::DEFAULT[:size] = [2, 0, 0, 2] # Array parsed by the extra above

require 'pagy/extras/i18n' # ensure the i18n extra is loaded

Pagy::I18n.load(
  { locale: 'en', filepath: Rails.root.join("config/locales/pagy.en.yml") }
)

# Pagy::VARS[:page_param] = :p # default page query param
# require 'pagy/extras/array'
# require 'pagy/extras/compact'
# require 'pagy/extras/countless'
# require 'pagy/extras/elasticsearch'
# require 'pagy/extras/headers'
# require 'pagy/extras/i18n'
# require 'pagy/extras/items'
# require 'pagy/extras/materialize'
# require 'pagy/extras/metadata'
# require 'pagy/extras/navs'
# require 'pagy/extras/overflow'
# require 'pagy/extras/plain'
# require 'pagy/extras/responsive'
# require 'pagy/extras/semantic'
# require 'pagy/extras/trim'
# require 'pagy/extras/url_for'
# require 'pagy/extras/arel'
