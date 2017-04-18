# ❯ be ruby script/bench_writing_events.rb
# Warming up --------------------------------------
#    redis event store   284.000  i/100ms
# Calculating -------------------------------------
#    redis event store      2.865k (± 3.1%) i/s -     14.484k in   5.060905s
# ^ MacBook Pro results

require 'benchmark/ips'
require 'securerandom'
require 'event_sourcery/redis'

redis = Redis.connect(port: ENV['BOXEN_REDIS_PORT'] || 6379)
event_store = EventSourcery::Redis::EventStore.new(redis)

def new_event
  EventSourcery::Event.new(type: :item_added,
                           aggregate_id: SecureRandom.uuid,
                           body: { 'something' => 'simple' })
end

Benchmark.ips do |b|
  b.report("redis event store") do
    event_store.sink(new_event)
  end
end
