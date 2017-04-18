RSpec.describe EventSourcery::Redis::EventStore do
  let(:supports_versions) { true }
  let(:redis) { $redis }
  subject(:event_store) { described_class.new(new_redis_connection) }
  let(:aggregate_id) { SecureRandom.uuid }

  describe '#sink' do
    it 'assigns auto incrementing event IDs' do
      event_store.sink(new_event)
      event_store.sink(new_event)
      event_store.sink(new_event)
      events = event_store.get_next_from(1)
      expect(events.count).to eq 3
      expect(events.map(&:id)).to eq [1, 2, 3]
    end

    it 'assigns UUIDs' do
      uuid = SecureRandom.uuid
      event_store.sink(new_event(uuid: uuid))
      event = event_store.get_next_from(1).first
      expect(event.uuid).to eq uuid
    end

    it 'returns true' do
      expect(event_store.sink(new_event)).to eq true
    end

    it 'serializes the event body' do
      time = Time.now
      event = new_event(body: { 'time' => time })
      expect(event_store.sink(event)).to eq true
      expect(event_store.get_next_from(1, limit: 1).first.body).to eq('time' => time.iso8601)
    end

    it 'writes multiple events' do
      event_store.sink([new_event(aggregate_id: aggregate_id, body: {e: 1}),
                        new_event(aggregate_id: aggregate_id, body: {e: 2}),
                        new_event(aggregate_id: aggregate_id, body: {e: 3})])
      events = event_store.get_next_from(1)
      expect(events.count).to eq 3
      expect(events.map(&:id)).to eq [1, 2, 3]
      expect(events.map(&:body)).to eq [{'e' => 1}, {'e' => 2}, {'e' => 3}]
      if supports_versions
        expect(events.map(&:version)).to eq [1, 2, 3]
      end
    end

    it 'sets the correct aggregates version' do
      event_store.sink([new_event(aggregate_id: aggregate_id, body: {e: 1}),
                        new_event(aggregate_id: aggregate_id, body: {e: 2})])
      # this will throw a unique constrain error if the aggregate version was not set correctly ^
      event_store.sink([new_event(aggregate_id: aggregate_id, body: {e: 1}),
                        new_event(aggregate_id: aggregate_id, body: {e: 2})])
      events = event_store.get_next_from(1)
      expect(events.count).to eq 4
      expect(events.map(&:id)).to eq [1, 2, 3, 4]
    end

    context 'with no existing aggregate stream' do
      it 'saves an event' do
        event = new_event(aggregate_id: aggregate_id,
                          type: :test_event_2,
                          body: { 'my' => 'data' })
        event_store.sink(event)
        events = event_store.get_next_from(1)
        expect(events.count).to eq 1
        expect(events.first.id).to eq 1
        expect(events.first.aggregate_id).to eq aggregate_id
        expect(events.first.type).to eq 'test_event_2'
        expect(events.first.body).to eq({ 'my' => 'data' }) # should we symbolize keys when hydrating events?
      end
    end

    context 'with an existing aggregate stream' do
      before do
        event_store.sink(new_event(aggregate_id: aggregate_id))
      end

      it 'saves an event' do
        event = new_event(aggregate_id: aggregate_id,
                         type: :test_event_2,
                         body: { 'my' => 'data' })
        event_store.sink(event)
        events = event_store.get_next_from(1)
        expect(events.count).to eq 2
        expect(events.last.id).to eq 2
        expect(events.last.aggregate_id).to eq aggregate_id
        expect(events.last.type).to eq :test_event_2.to_s # shouldn't you get back what you put in, a symbol?
        expect(events.last.body).to eq({ 'my' => 'data' }) # should we symbolize keys when hydrating events?
      end
    end
  end

  describe '#get_next_from' do
    it 'gets a subset of events' do
      event_store.sink(new_event(aggregate_id: aggregate_id))
      event_store.sink(new_event(aggregate_id: aggregate_id))
      expect(event_store.get_next_from(1, limit: 1).map(&:id)).to eq [1]
      expect(event_store.get_next_from(2, limit: 1).map(&:id)).to eq [2]
      expect(event_store.get_next_from(1, limit: 2).map(&:id)).to eq [1, 2]
    end

    it 'returns the event as expected' do
      event_store.sink(new_event(aggregate_id: aggregate_id, type: 'item_added', body: { 'my' => 'data' }))
      event = event_store.get_next_from(1, limit: 1).first
      expect(event.aggregate_id).to eq aggregate_id
      expect(event.type).to eq 'item_added'
      expect(event.body).to eq({ 'my' => 'data' })
      expect(event.created_at).to be_instance_of(Time)
    end

    it 'filters by event type' do
      event_store.sink(new_event(aggregate_id: aggregate_id, type: 'user_signed_up'))
      event_store.sink(new_event(aggregate_id: aggregate_id, type: 'item_added'))
      event_store.sink(new_event(aggregate_id: aggregate_id, type: 'item_added'))
      event_store.sink(new_event(aggregate_id: aggregate_id, type: 'item_rejected'))
      event_store.sink(new_event(aggregate_id: aggregate_id, type: 'user_signed_up'))
      events = event_store.get_next_from(1, event_types: ['user_signed_up'])
      expect(events.count).to eq 2
      expect(events.map(&:id)).to eq [1, 5]
    end
  end

  describe '#latest_event_id' do
    it 'returns the latest event id' do
      event_store.sink(new_event(aggregate_id: aggregate_id))
      event_store.sink(new_event(aggregate_id: aggregate_id))
      expect(event_store.latest_event_id).to eq 2
    end

    context 'with no events' do
      it 'returns 0' do
        expect(event_store.latest_event_id).to eq 0
      end
    end

    context 'with event type filtering' do
      it 'gets the latest event ID for a set of event types' do
        event_store.sink(new_event(aggregate_id: aggregate_id, type: 'type_1'))
        event_store.sink(new_event(aggregate_id: aggregate_id, type: 'type_1'))
        event_store.sink(new_event(aggregate_id: aggregate_id, type: 'type_2'))

        expect(event_store.latest_event_id(event_types: ['type_1'])).to eq 2
        expect(event_store.latest_event_id(event_types: ['type_2'])).to eq 3
        expect(event_store.latest_event_id(event_types: ['type_1', 'type_2'])).to eq 3
      end
    end
  end

  describe '#get_events_for_aggregate_id' do
    it 'gets events for a specific aggregate id' do
      event_store.sink(new_event(aggregate_id: aggregate_id, type: 'item_added', body: { 'my' => 'body' }))
      event_store.sink(new_event(aggregate_id: aggregate_id))
      event_store.sink(new_event(aggregate_id: SecureRandom.uuid))
      events = event_store.get_events_for_aggregate_id(aggregate_id)
      expect(events.map(&:id)).to eq([1, 2])
      expect(events.first.aggregate_id).to eq aggregate_id
      expect(events.first.type).to eq 'item_added'
      expect(events.first.body).to eq({ 'my' => 'body' })
      expect(events.first.created_at).to be_instance_of(Time)
    end
  end

  # TODO: this is a slow spec, optimise
  describe '#each_by_range' do
    before do
      (1..2001).each do |i|
        event_store.sink(new_event(aggregate_id: aggregate_id,
                                   type: 'item_added',
                                   body: {}))
      end
    end

    def events_by_range(*args)
      [].tap do |events|
        event_store.each_by_range(*args) do |event|
          events << event
        end
      end
    end

    context "the range doesn't include the latest event ID" do
      it 'returns only the events in the range' do
        events = events_by_range(1, 20)
        expect(events.count).to eq 20
        expect(events.map(&:id)).to eq((1..20).to_a)
      end
    end

    context 'the range includes the latest event ID' do
      it 'returns all the events' do
        events = events_by_range(1, 2001)
        expect(events.count).to eq 2001
        expect(events.map(&:id)).to eq((1..2001).to_a)
      end
    end

    context 'the range exceeds the latest event ID' do
      it 'returns all the events' do
        begin
          events = events_by_range(1, 2050)
          expect(events.count).to eq 2001
          expect(events.map(&:id)).to eq((1..2001).to_a)
        rescue
          binding.pry
        end
      end
    end

    context 'the range filters by event type' do
      it 'returns only events of the given type' do
        begin
          expect(events_by_range(1, 2001, event_types: ['user_signed_up']).count).to eq 0
          expect(events_by_range(1, 2001, event_types: ['item_added']).count).to eq 2001
        rescue
          binding.pry
        end
      end
    end
  end

  describe '#subscribe' do
    let(:aggregate_id) { SecureRandom.uuid }
    let(:event) { new_event(aggregate_id: aggregate_id) }
    let(:subscription_master) { spy(EventSourcery::EventStore::SignalHandlingSubscriptionMaster) }

    it 'notifies of new events' do
      event_store.subscribe(from_id: 1,
                            on_subscribe: proc { EventSourcery::Redis::EventStore.new(new_redis_connection).sink(event) },
                            subscription_master: subscription_master) do |events|
        @events = events
        throw :stop
      end
      expect(@events.count).to eq 1
      expect(@events.first.aggregate_id).to eq aggregate_id
    end
  end

  context 'optimistic concurrency control' do
    def save_event(expected_version: nil)
      event_store.sink(new_event(aggregate_id: aggregate_id,
                       type: :billing_details_provided,
                       body: { my_event: 'data' }),
                       expected_version: expected_version)
    end

    def add_event
      event_store.sink(new_event(aggregate_id: aggregate_id))
    end

    def last_event
      event_store.get_next_from(1).last
    end

    def aggregate_version
      $redis.get("aggregate_versions_#{aggregate_id}").to_i
    end

    context "when the aggregate doesn't exist" do
      context 'and the expected version is correct - 0' do
        it 'saves the event with and sets the aggregate version to version 1' do
          save_event(expected_version: 0)
          expect(last_event[:version]).to eq 1
          expect(aggregate_version).to eq 1
        end
      end

      context 'and the expected version is incorrect - 1' do
        it 'raises a ConcurrencyError' do
          expect {
            save_event(expected_version: 1)
          }.to raise_error(EventSourcery::ConcurrencyError)
        end
      end

      context 'with no expected version' do
        it 'saves the event with and sets the aggregate version to version 1' do
          save_event
          expect(last_event[:version]).to eq 1
          expect(aggregate_version).to eq 1
        end
      end
    end

    context 'when the aggregate exists' do
      before do
        add_event
      end

      context 'with an incorrect expected version - 0' do
        it 'raises a ConcurrencyError' do
          expect {
            save_event(expected_version: 0)
          }.to raise_error(EventSourcery::ConcurrencyError)
        end
      end

      context 'with a correct expected version - 1' do
        it 'saves the event with and sets the aggregate version to version 2' do
          save_event
          expect(last_event[:version]).to eq 2
          expect(aggregate_version).to eq 2
        end
      end

      context 'with no aggregate version' do
        it 'automatically sets the version on the event and aggregate' do
          save_event
          expect(last_event[:version]).to eq 2
          expect(aggregate_version).to eq 2
        end
      end
    end

    it 'allows overriding the created_at timestamp for events' do
      time = Time.parse('2016-10-14T00:00:00.646191Z')
      event_store.sink(new_event(aggregate_id: aggregate_id,
                                 type: :billing_details_provided,
                                 body: { my_event: 'data' },
                                 created_at: time))
      expect(last_event[:created_at]).to eq time
    end

    it 'defaults to now() when no created_at timestamp is supplied' do
      event_store.sink(new_event(aggregate_id: aggregate_id,
                                 type: :billing_details_provided,
                                 body: { my_event: 'data' }))
      expect(last_event[:created_at]).to be_instance_of(Time)
    end
  end
end
