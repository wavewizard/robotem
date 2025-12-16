defmodule SorterTest do
  use ExUnit.Case
  alias Robotem.Event

  defmodule TestConsumer do
    use GenStage

    def start_link(test_pid) do
      GenStage.start_link(__MODULE__, test_pid)
    end

    def init(test_pid) do
      {:consumer, test_pid, subscribe_to: [Robotem.Sorter]}
    end

    def handle_events(events, _from, test_pid) do
      # Send the events to the test process
      send(test_pid, {:events, events})

      # We don't need to do anything else with the events, so we return an empty list
      {:noreply, [], test_pid}
    end
  end

  setup do
    # Start a test producer
    {:ok, producer} = TestGenerator.start_link([])
    # Start the sorter subscribing to the test producer
    {:ok, sorter} = Robotem.Sorter.start_link(subscription: [TestGenerator])
    {:ok, producer: producer, sorter: sorter}
  end

  test "should process event when event is expected", %{producer: producer, sorter: _sorter} do
    event1 = %{seq: 1, event_type: "Test", event_data: %{a: 1}, meta_data: %{}}
    event2 = %{event1 | seq: 2}
    GenStage.call(producer, {:notify, event1})
    GenStage.call(producer, {:notify, event2})

    # Wait for processing
    :timer.sleep(100)
    GenStage.stream([Robotem.Sorter]) |> Enum.take(2)

    state = GenStage.call(Robotem.Sorter, :get_state)
    assert state.buffer == %{}
    assert state.last_seen == 2
  end

  test "process expected event, buffer unexpected events, and process when expected event is received",
       %{producer: producer, sorter: _sorter} do
    # Step 1: Send expected event seq: 1
    event = %{seq: 1, event_type: "Test", event_data: %{a: 1}, meta_data: %{}}

    GenStage.call(producer, {:notify, event})
    :timer.sleep(500)

    GenStage.stream([Robotem.Sorter]) |> Enum.take(1)
    state = GenStage.call(Robotem.Sorter, :get_state)
    assert state.buffer == %{}
    assert state.last_seen == 1

    # Step 2: Send unexpected events seq: 3,4,5,6
    Enum.each(3..6, fn seq ->
      event_t = %{event | seq: seq}
      GenStage.call(producer, {:notify, event_t})
    end)

    :timer.sleep(100)
    GenStage.stream([Robotem.Sorter])
    state = GenStage.call(Robotem.Sorter, :get_state)

    assert state.buffer ==
             %{
               3 => %Event{seq: 3, event_type: "Test", meta_data: %{}, event_data: %{a: 1}},
               4 => %Event{seq: 4, event_type: "Test", meta_data: %{}, event_data: %{a: 1}},
               5 => %Event{seq: 5, event_type: "Test", meta_data: %{}, event_data: %{a: 1}},
               6 => %Event{seq: 6, event_type: "Test", meta_data: %{}, event_data: %{a: 1}}
             }

    assert state.last_seen == 1

    # Step 3: Send next expected event seq: 2
    event2 = %{seq: 2, event_type: "Test", event_data: %{a: 1}, meta_data: %{}}
    GenStage.call(producer, {:notify, event2})
    :timer.sleep(100)
    GenStage.stream([Robotem.Sorter])
    state = GenStage.call(Robotem.Sorter, :get_state)
    assert state.buffer == %{}
    assert state.last_seen == 6
  end

  test "process out-of-order events and buffer until expected sequence is received",
       %{producer: producer, sorter: _sorter} do
    # Step 1: Send out-of-order events with seq_no 2, 4, 5
    Enum.each([2, 4, 5], fn seq ->
      event = %{seq: seq, event_type: "test", meta_data: %{}, event_data: %{a: 1}}
      GenStage.call(producer, {:notify, event})
    end)

    {:ok, _c} = TestConsumer.start_link(self())
    # We should not receive any events yet
    refute_receive {:events, _}, 500

    # Verify the state: buffer should contain 2, 4, 5, and last_seen should be 0 (or initial value)
    state = GenStage.call(Robotem.Sorter, :get_state)

    assert state.buffer == %{
             2 => %Event{seq: 2, event_type: "test", meta_data: %{}, event_data: %{a: 1}},
             4 => %Event{seq: 4, event_type: "test", meta_data: %{}, event_data: %{a: 1}},
             5 => %Event{seq: 5, event_type: "test", meta_data: %{}, event_data: %{a: 1}}
           }

    assert state.last_seen == 0

    # Step 2: Send the expected event with seq_no 1
    event1 = %{seq: 1, event_type: "test", meta_data: %{}, event_data: %{a: 1}}
    GenStage.call(producer, {:notify, event1})

    # We should receive events 1 and 2
    assert_receive {:events,
                    [
                      %Event{seq: 1, event_type: "test", event_data: %{a: 1}, meta_data: %{}},
                      %Event{seq: 2, event_type: "test", event_data: %{a: 1}, meta_data: %{}}
                    ]},
                   1000

    # Verify the state: buffer should contain 4 and 5, and last_seen should be 2
    state = GenStage.call(Robotem.Sorter, :get_state)

    assert state.buffer == %{
             4 => %Event{seq: 4, event_type: "test", event_data: %{a: 1}, meta_data: %{}},
             5 => %Event{seq: 5, event_type: "test", event_data: %{a: 1}, meta_data: %{}}
           }

    assert state.last_seen == 2

    # Step 3: Send the expected event with seq_no 3
    GenStage.call(
      producer,
      {:notify, %{seq: 3, event_type: "test", event_data: %{a: 1}, meta_data: %{}}}
    )

    # We should receive events 3, 4, and 5
    assert_receive {:events,
                    [
                      %{seq: 3, event_type: "test", event_data: %{a: 1}, meta_data: %{}},
                      %{seq: 4, event_type: "test", event_data: %{a: 1}, meta_data: %{}},
                      %{seq: 5, event_type: "test", event_data: %{a: 1}, meta_data: %{}}
                    ]},
                   1000

    # Verify the state: buffer should be empty, and last_seen should be 5
    state = GenStage.call(Robotem.Sorter, :get_state)
    assert state.buffer == %{}
    assert state.last_seen == 5
  end

  # defp flush_mailbox do
  #   receive do
  #     _ -> flush_mailbox()
  #   after
  #     0 -> :ok
  #   end
  # end

  def capture_events(timeout \\ 1000) do
    receive do
      {:events, events} -> [events | capture_events(timeout)]
    after
      timeout -> []
    end
  end
end
