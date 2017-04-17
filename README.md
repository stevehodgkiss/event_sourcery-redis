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
tracker = EventSourcery::Redis::Tracker.new(redis)

# Configure EventSourcery to use this store by default
EventSourcery.configure do |config|
  config.event_store = event_store
  config.event_tracker = tracker
end
```

Projectors:

```
class ItemsProjector
  include EventSourcery::EventProcessing::EventStreamProcessor

  def initializer(tracker, redis)
    @tracker = tracker
    @redis = redis
  end

  process ItemAdded do |event|
    redis.push('item_names', event.body.fetch('name'))
  end

  private

  attr_reader :redis
end
```
