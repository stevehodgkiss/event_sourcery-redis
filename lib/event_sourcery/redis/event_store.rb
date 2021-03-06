require 'redis/lua'
require 'msgpack'

module EventSourcery
  module Redis
    class EventStore
      include EventSourcery::EventStore::EachByRange

      WRITE_EVENTS_LUA = <<-EOS
      local return_value = 1
      local events = cmsgpack.unpack(KEYS[1])
      local expected_version = tonumber(KEYS[2])

      for i=1, #events do
        local id = tonumber(redis.call('hlen', 'events')) + 1

        local event = events[i]

        local current_version = redis.call('get', 'aggregate_versions_' .. event['aggregate_id'])
        if current_version == false then
          current_version = 0
        end
        if expected_version ~= nil and current_version ~= expected_version then
          return_value = 0
        end

        local version = redis.call('incrby', 'aggregate_versions_' .. event['aggregate_id'], 1)
        event['version'] = version

        redis.call('rpush', 'aggregate_' .. event['aggregate_id'], id)
        redis.call('hset', 'events', id, cmsgpack.pack(event))
        redis.call('hset', 'latest_event_id_for_type', event['type'], id)
        redis.call('set', 'latest_event_id', id)
        redis.call('publish', 'new_event', id)
      end
      return return_value
      EOS

      def initialize(redis, event_builder: EventSourcery.config.event_builder)
        @redis = redis
        @event_builder = event_builder
        # TODO: this should probably live somewhere else
        redis.register_script(:write_events, WRITE_EVENTS_LUA)
      end

      def sink(event_or_events, expected_version: nil)
        events = Array(event_or_events)
        aggregate_ids = events.map(&:aggregate_id).uniq
        raise AtomicWriteToMultipleAggregatesNotSupported unless aggregate_ids.count == 1
        events_s = events.map do |event|
          event = {
            uuid: event.uuid,
            aggregate_id: event.aggregate_id,
            type: event.type,
            body: event.body,
            created_at: (event.created_at&.utc || Time.now.utc).iso8601(6).to_s
          }.reject { |k, v| v.nil? }
          event
        end
        message = MessagePack.pack(events_s)
        return_value = @redis.run_script(:write_events, keys: [message, expected_version])
        if return_value != 1
          raise ConcurrencyError
        end
        true
      end

      def get_next_from(from_id, limit: 1000, event_types: nil)
        event_id = from_id
        limit_id = from_id + limit
        events = {}
        begin
          event = get_event(event_id)
          if event && (event_types.nil? || event_types.include?(event[:type]))
            events[event_id] = event
          end
          event_id += 1
        end while event_id < limit_id && event != nil
        events.map do |event_id, event|
          build_event(event)
        end
      end

      def latest_event_id(event_types: nil)
        event_id = if event_types
          event_types.map do |type|
            redis.hget('latest_event_id_for_type', type).to_i
          end.max
        else
          redis.get('latest_event_id').to_i
        end
        event_id || 0
      end

      def get_events_for_aggregate_id(aggregate_id)
        event_hashes = redis.lrange("aggregate_#{aggregate_id}", 0, -1).map { |id| get_event(id) }
        event_hashes.map do |event_hash|
          build_event(event_hash)
        end
      end

      def subscribe(from_id:, event_types: nil, on_subscribe: nil, subscription_master:, &block)
        poll_waiter = PubSubPollWaiter.new(redis.dup, on_subscribe: on_subscribe)
        args = {
          poll_waiter: poll_waiter,
          event_store: self,
          from_event_id: from_id,
          event_types: event_types,
          subscription_master: subscription_master,
          on_new_events: block
        }
        EventSourcery::EventStore::Subscription.new(args).tap do |s|
          s.start
        end
      end

      private

      attr_reader :redis, :event_builder

      def build_event(attributes)
        event_builder.build(attributes)
      end

      def get_event(event_id)
        event_msg = redis.hget('events', event_id)
        if event_msg
          parsed_event = MessagePack.unpack(event_msg)
          parsed_event[:id] = event_id
          symbolize_hash(parsed_event)
        end
      end

      def symbolize_hash(hash)
        Hash[hash.map{ |(k,v)| [k.to_sym, v] }]
      end
    end
  end
end
