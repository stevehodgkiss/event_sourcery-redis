# ❯ be ruby script/bench_writing_events.rb
# Warming up --------------------------------------
#    redis event store   304.000  i/100ms
# Calculating -------------------------------------
#    redis event store      3.230k (± 4.9%) i/s -     16.112k in   5.000765s
# ^ MacBook Pro results

require 'benchmark/ips'
require 'securerandom'
require 'event_sourcery/redis'
require 'hiredis'

redis = Redis.connect(port: ENV['BOXEN_REDIS_PORT'] || 6379, driver: :hiredis)
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
