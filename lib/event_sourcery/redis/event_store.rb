require 'redis/lua'

module EventSourcery
  module Redis
    class EventStore
      include EventSourcery::EventStore::EachByRange

      WRITE_EVENTS_LUA = <<-EOS
      local events = unpack(ARGV)

      for i=1, #ARGV do
        // since Redis is single threaded, only one of this function will be
        // executing at any given time, if that wasn't the case there would be a
        // race condition where events would get overwritten.
        local id = tonumber(redis.call('hlen', 'events')) + 1

        local event = ARGV[i]
        local decoded_event = cjson.decode(event)

        local version = redis.call('incrby', 'aggregate_versions_' .. decoded_event['aggregate_id'], 1)
        decoded_event['version'] = version

        redis.call('rpush', 'aggregate_' .. decoded_event['aggregate_id'], id)
        redis.call('hset', 'events', id, cjson.encode(decoded_event))
        redis.call('hset', 'latest_event_id_for_type', decoded_event['type'], id)
        redis.call('set', 'latest_event_id', id)
        redis.call('publish', 'new_event', id)
      end
      return 1
      EOS

      def initialize(redis, event_builder: EventSourcery.config.event_builder)
        @redis = redis
        @event_builder = event_builder
        # TODO: this should probably live somewhere else
        redis.register_script(:write_events, WRITE_EVENTS_LUA)
      end

      def sink(event_or_events)
        events = Array(event_or_events)
        aggregate_ids = events.map(&:aggregate_id).uniq
        raise AtomicWriteToMultipleAggregatesNotSupported unless aggregate_ids.count == 1
        redis.watch("aggregate_versions_#{events.last[:aggregate_id]}")
        events_s = events.map do |event|
          event = {
            uuid: event.uuid,
            aggregate_id: event.aggregate_id,
            type: event.type,
            body: event.body,
            created_at: event.created_at || Time.now
          }
          JSON.dump(event)
        end
        @redis.run_script(:write_events, argv: events_s)
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
        event_json = redis.hget('events', event_id)
        if event_json
          parsed_event = JSON.parse(event_json, symbolize_names: true)
          parsed_event[:id] = event_id
          parsed_event
        end
      end
    end
  end
end
