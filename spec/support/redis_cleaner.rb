RSpec.configure do |config|
  config.before(:each) do
    $redis = new_redis_connection
    $redis.flushdb
  end
end
