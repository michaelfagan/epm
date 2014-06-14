source 'https://rubygems.org'

gem 'rails', '4.1.1'

# assets
gem 'sass-rails'
gem 'uglifier'
gem 'jquery-rails'
gem 'jquery-ui-rails'

# authorization and authentication
gem 'devise'
gem 'cancancan'

# config
gem 'figaro' # secrets
gem 'configurable_engine' # editable within app

# geo stuff
gem 'geokit-rails'
gem 'geokit-nominatim'
gem 'leaflet-rails'

# ui
gem 'rinku' # URL auto-linking
gem 'simple_calendar'
gem 'kaminari' # pagination
gem 'indefinite_article' # prepends the correct "a" or "an" before a noun

# misc gems
gem 'strip_attributes' # clean form input
gem 'icalendar' # export
gem 'whenever', :require => false # cron

group :production do
  # Heroku
  gem 'pg'
  gem 'rails_12factor'

  # Dreamhost Shared Hosting
  # gem 'mysql2'
  # gem 'fcgi'
  # gem 'therubyracer'
end

group :development, :test do
  gem 'pg'

  gem 'rspec-rails'
  gem 'letter_opener'

  gem 'factory_girl_rails'
  gem 'faker'
end

group :test do
  gem 'capybara'
  gem 'capybara-webkit'
  gem 'database_cleaner'
end