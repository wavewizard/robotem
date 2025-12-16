defmodule Robotem.Runner.SingleTest do
  use ExUnit.Case, async: false
  alias Robotem.Event

  setup do
    Memento.Table.create(Robotem.ProcessRegistry)
    Memento.Table.create(Robotem.ProcessConfiguration)
    Memento.Table.clear(Robotem.ProcessRegistry)
    Memento.Table.clear(Robotem.ProcessConfiguration)
    process_module = Robotem.Test.TestProcess

    process_attrs = %{
      process_module: process_module,
      runner_module: :single,
      description: "Test Process",
      process_type: {:source, :process}
    }

    {:ok, _conf} = Robotem.ProcessConfiguration.add(process_attrs)

    Robotem.Controller.start_link([])

    Robotem.Controller.register_process(process_module)
    :timer.sleep(500)
    runner_pid = Robotem.ProcessRegistry.get_pid(process_module)
    # true = is_pid(runner_pid)
    {:ok, process_runner: runner_pid}
  end

  test "processes a new event successfully", %{process_runner: pr} do
    # Expects an Robotem.Event
    event = %Event{
      seq: 1,
      event_type: Robotem.Test.Event.InvoiceAdded,
      event_data: %{date: nil, amount: 100, issued_to_id: "1234"},
      meta_data: %{timestamp: ~U[2024-01-01 00:00:00Z]}
    }

    # Send the event to the Process Runner
    GenServer.cast(pr, {:new_event, event})

    :timer.sleep(100)

    # Assert that the task is spawned and completed successfully
    assert %{tasks: %{}} = GenServer.call(pr, :get_state)
  end

  test "task fails", %{process_runner: pr} do
    event = %Event{
      event_type: Robotem.Test.Event.Failed,
      event_data: %{afield: "1234"},
      seq: 1,
      meta_data: %{timestamp: ~U[2024-01-01 00:00:00Z]}
    }

    # Send the event to the Process Runner
    GenServer.cast(pr, {:new_event, event})
    :timer.sleep(1500)

    # That Task should be in dlq now
    assert %{tasks: %{}, dlq: dlq} = GenServer.call(pr, :get_state)
    assert dlq != []
  end
end
