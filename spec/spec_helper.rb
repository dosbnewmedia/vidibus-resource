require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
end

require 'rr'
require 'database_cleaner'
require 'webmock/rspec'
require 'vidibus-resource'

require 'support/models'
require 'support/services'

Mongoid.configure do |config|
  config.connect_to('vidibus-resource_test')
end

RSpec.configure do |config|
  config.include WebMock::API
  config.mock_with :rr

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end
  
  config.before(:each) do
    DatabaseCleaner.start
  end
  
  config.after(:each) do
    DatabaseCleaner.clean
  end
end
