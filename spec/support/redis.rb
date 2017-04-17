module RedisHelper
  def new_redis_connection
    Redis.connect(port: ENV['BOXEN_REDIS_PORT'] || 6379)
  end
end

RSpec.configure do |config|
  config.include(RedisHelper)
end
