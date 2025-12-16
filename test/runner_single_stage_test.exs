defmodule RunnerSingleStageTest do
  use ExUnit.Case
  alias Robotem.Runner.SingleStage

  setup do
    {:ok, producer} = TestGenerator.start_link([])
    # Start the sorter subscribing to the test producer
    {:ok, sorter} = Robotem.Sorter.start_link(subscription: [TestGenerator])
    {:ok, producer: producer, sorter: sorter}
  end

  test "Should start the runner", %{producer: producer, sorter: _sorter} do
    SingleStage.start_link(%{process_module: Robotem.Test.TestProcess, last_seen: 0})

    event = %{
      event_type: Robotem.Test.Event.InvoiceAdded,
      event_data: %{date: nil, amount: 100, issued_to_id: "1234"}
    }

    meta = %{seq: 1, timestamp: ~U[2024-01-01 00:00:00Z]}
    GenStage.call(producer, {:notify, %{seq: 1, event_type: "test"}})
    GenStage.call(producer, {:notify, %{seq: 2, event_type: "test"}})

    state = GenStage.call(Robotem.Sorter, :get_state)
    {:timer.sleep(1000)}
    assert state.buffer == %{}
    assert state.last_seen == 2
  end
end
