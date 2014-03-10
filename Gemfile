source 'https://rubygems.org'

gem 'rails', "4.1.0.rc1"

gem 'pg'

# assets
gem 'sass-rails'
gem 'uglifier'
gem 'jquery-rails'
gem 'jquery-ui-rails'

# authoerization and authentication
gem 'devise'
gem 'cancancan'

gem 'configurable_engine' # site-wide config

gem 'strip_attributes'

gem 'rinku' # URL auto-linking

group :production do
  gem 'rails_12factor'
end

# normally these are just used in development and test;
# included for production here as well, as production now is a demo using demo data generated from factories
gem 'factory_girl_rails'
gem 'faker'

group :development, :test do
  gem 'rspec-rails'
  gem 'letter_opener'
end

group :test do
  gem 'capybara'
  gem 'capybara-webkit'
  gem 'database_cleaner'
end