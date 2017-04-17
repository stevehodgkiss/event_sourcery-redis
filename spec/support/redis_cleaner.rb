RSpec.configure do |config|
  config.before(:each) do
    $redis.flushdb
  end
end
