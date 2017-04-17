$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'event_sourcery/redis'
require 'pry'

$redis = Redis.connect(port: ENV['BOXEN_REDIS_PORT'] || 6379)

Dir.glob(File.dirname(__FILE__) + '/support/**/*.rb') { |f| require f }
