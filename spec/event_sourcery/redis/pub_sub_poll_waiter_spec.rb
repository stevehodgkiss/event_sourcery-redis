RSpec.describe EventSourcery::Redis::PubSubPollWaiter do
  let(:waiter) { described_class.new(new_redis_connection, on_subscribe: proc { event_store.sink(new_event) }) }
  subject(:event_store) { EventSourcery::Redis::EventStore.new(new_redis_connection) }

  it 'calls the block on new events' do
    Timeout.timeout(5) do
      waiter.poll do
        @called = true
        throw :stop
      end
    end
    expect(@called).to eq true
  end
end
