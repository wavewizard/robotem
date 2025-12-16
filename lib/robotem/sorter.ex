defmodule Robotem.Sorter do
  @moduledoc """

  `Robotem.Sorter` is a GenStage-based module designed to process and order events based on their sequence numbers (`seq`).

  This module acts as a producer-consumer that receives events from a producer, buffers out-of-order events, and emits events in the correct sequence. It ensures that events are processed in the order of their `seq` values, even if they arrive out of order.

  ## Key Features
  - **Buffering Out-of-Order Events**: Events with sequence numbers higher than the expected `last_seen + 1` are buffered until the missing events are received.
  - **Sequential Event Emission**: Events are emitted in the correct order as soon as the expected sequence number is received.
  - **State Management**: The module maintains a buffer of out-of-order events and tracks the `last_seen` sequence number to determine the next expected event.

  ## Usage
  The `Robotem.Sorter` module is typically used in a pipeline with a producer that generates events and a consumer that processes the ordered events. It ensures that events are delivered to the consumer in the correct sequence.

  ### Example Setup
  ```elixir
  {:ok, producer} = GenStage.start_link(MyProducer, [])
  {:ok, sorter} = GenStage.start_link(Robotem.Sorter, subscription: producer)
  {:ok, consumer} = GenStage.start_link(MyConsumer, [])
  GenStage.sync_subscribe(consumer, to: sorter)

  ### State Structure
  The module maintains its state using a %Robotem.Sorter{} struct with the following fields:

    buffer: A map that stores out-of-order events, keyed by their seq values.

    last_seen: The sequence number of the last event that was emitted.

  ## Functions

  - `start_link/1`: Starts the `Robotem.Sorter` process and links it to the calling process.
  - `init/1`: Initializes the module with an empty buffer and `last_seen` set to 0.
  - `handle_events/3`: Processes incoming events, buffers out-of-order events, and emits events in the correct sequence.
  - `handle_call/3`: Handles synchronous calls to retrieve the current state or buffer.
  - `loop_emit/3`: A helper function that recursively emits events in sequence from the buffer.

  ## Example
  # Send events out of order
  GenStage.call(producer, {:notify, %{seq: 2, event_type: "test"}})
  GenStage.call(producer, {:notify, %{seq: 4, event_type: "test"}})
  GenStage.call(producer, {:notify, %{seq: 1, event_type: "test"}})

  # The consumer will receive events in the correct order: [1, 2]
  assert_receive {:events, [%{seq: 1, event_type: "test"}, %{seq: 2, event_type: "test"}]}
  """
  use GenStage

  alias Robotem.Event

  defstruct buffer: %{}, last_seen: 0

  def start_link(args) do
    GenStage.start_link(__MODULE__, args,
      producer: [max_demand: 1000, min_demand: 1],
      name: __MODULE__
    )
  end

  def init(args) do
    IO.inspect(args[:subscription])
    initial_state = %__MODULE__{buffer: %{}, last_seen: 0}

    {:producer_consumer, initial_state,
     subscribe_to: args[:subscription], dispatcher: GenStage.BroadcastDispatcher}
  end

  @doc """
  Handles incoming events in a GenStage consumer, managing a buffer to ensure events are processed in sequence.

  This function receives a list of events, filters out demand-related messages, and processes the actual events. It maintains a buffer to store events based on their sequence numbers and emits them in the correct order. The buffer ensures that events are not emitted out of sequence, even if they are received out of order.

  ### Parameters

    * `events` - A list of events received from the producer.
    * `_from` - The producer that sent the events (not used in this function).
    * `state` - The current state of the consumer, containing the buffer and the last seen sequence number.

  ### Returns

    * `{:noreply, emitted, new_state}` - A GenStage reply indicating no reply is needed, the list of emitted events, and the updated state.

  ### State Management

  The state is a map containing:

    * `:buffer` - A map storing events with their sequence numbers as keys.
    * `:last_seen` - The highest sequence number of an event that has been emitted.

  ### Event Processing Logic

  1. **Filtering Events:**
     - Events of the form `{:"$gen_consumer", _, _}` are filtered out as they represent demand messages and are not actual events to be processed.

  2. **Updating the Buffer:**
     - The remaining events are stored in the buffer map, indexed by their `seq` value.

  3. **Emitting Events:**
     - The function attempts to emit events starting from the `expected_seq`, which is one more than the last seen sequence number.
     - Events are emitted in sequence order, and the buffer is updated accordingly.

  4. **Updating State:**
     - If any events are emitted, the `last_seen` sequence number is updated to the highest sequence number of the emitted events.
     - The buffer and the updated `last_seen` value constitute the new state.

  ### Assumptions

    * Each event has a `seq` field representing its sequence number.
    * Events are expected to arrive with increasing sequence numbers, but may be out of order.
    * Demand messages are of the form `{:"$gen_consumer", _, _}` and are ignored in this function.

  """

  def handle_events(events, _from, state) do
    mapped_events = events |> Enum.map(&map_event(&1))

    {actual_events, _demand_messages} =
      Enum.split_with(mapped_events, fn
        {:"$gen_consumer", _, _} -> false
        _ -> true
      end)

    buffer =
      Enum.reduce(actual_events, state.buffer, fn event, buf ->
        Map.put(buf, event.seq, event)
      end)

    emitted = []
    expected_seq = state.last_seen + 1

    {buffer, emitted} = loop_emit(buffer, emitted, expected_seq)

    new_last_seen =
      if emitted != [], do: Enum.max_by(emitted, & &1.seq).seq, else: state.last_seen

    new_state = %{state | buffer: buffer, last_seen: new_last_seen}

    {:noreply, emitted, new_state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, [], state}
  end

  def handle_call(:get_buffer, _from, state) do
    {:reply, state.buffer, [], state}
  end

  defp loop_emit(buffer, emitted, seq) do
    if Map.has_key?(buffer, seq) do
      event = Map.get(buffer, seq)
      buffer = Map.delete(buffer, seq)
      emitted = emitted ++ [event]
      loop_emit(buffer, emitted, seq + 1)
    else
      {buffer, emitted}
    end
  end

  defp map_event(payload) do
    # Normally we need to augment the meta_data
    %Event{
      seq: payload.seq,
      event_type: payload.event_type,
      event_data: payload.event_data,
      meta_data: payload.meta_data
    }
  end
end
