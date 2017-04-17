module EventSourcery
  module Redis
    class PubSubPollWaiter
      def initialize(redis, on_subscribe: proc {})
        @redis = redis
        @on_subscribe = on_subscribe
      end

      def poll(&block)
        catch(:stop) do
          @redis.subscribe('new_event') do |on|
            on.subscribe do |_, _|
              @on_subscribe.call
            end
            on.message do |channel, message|
              block.call
            end
          end
        end
      end

      def shutdown!
      end
    end
  end
end
