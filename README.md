# EventSourcery::Redis

Redis EventStore implementation for use with EventSourcery.

## Usage

Gemfile:

```
gem 'event_sourcery-redis'
```

Configure:

```
require 'event_sourcery/redis'
redis = Redis.new(port: ENV['BOXEN_REDIS_PORT'] || 6379)
event_store = EventSourcery::Redis::EventStore.new(redis)

# Configure EventSourcery to use this store by default
EventSourcery.configure do |config|
  config.event_store = event_store
end
```
