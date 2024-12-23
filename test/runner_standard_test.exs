defmodule Robotem.Runner.StandardTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  alias Robotem.Runner.Standard
  alias Robotem.Controller

  setup do
    process = Robotem.Test.TestProcess
    runner = Robotem.Runner.Standard
    {:ok, runner_process} = Robotem.register_process(process, runner)
    {:ok, process_runner: runner_process}
  end

  test "processes a new event successfully", %{process_runner: pr} do
    event = %{
      event_type: Robotem.Test.Event.InvoiceAdded,
      event_data: %{date: nil, amount: 100, issued_to_id: "1234"}
    }

    meta = %{seq: 1, timestamp: ~U[2024-01-01 00:00:00Z]}

    # Send the event to the Process Runner
    GenServer.cast(pr, {:new_event, event, meta})
    :timer.sleep(500)

    # Assert that the task is spawned and completed successfully
    assert 1 == 2
  end

  test "task fails", %{process_runner: pr} do
    event = %{
      event_type: Robotem.Test.Event.Failed,
      event_data: %{afield: "1234"}
    }

    meta = %{seq: 1, timestamp: ~U[2024-01-01 00:00:00Z]}

    # Send the event to the Process Runner
    GenServer.cast(pr, {:new_event, event, meta})
    :timer.sleep(8000)

    # Assert that the task is spawned and completed successfully
    assert 1 == 2
  end
end
