defmodule RobotemTest do
  use ExUnit.Case
  alias Robotem
  alias Robotem.TestEvent
  alias Eventos.Stream
  doctest Robotem

  def setup_all do
  end

  test "register process" do
    if Robotem.registered?(TestProcess) do
      Robotem.delete_process(TestProcess)
    end

    assert {:ok, pid} = Robotem.register_process(TestProcess, TestRunner)
    # we should see process is registered with its name
    assert {TestProcess, %{runner: TestRunner}} = Robotem.ProcessRegistry.get_robotem_process(pid)
    # also we should see process id is registered in events registry
    assert TestProcess.interested() == Robotem.EventRegistry.get_events(pid)
  end

  test "removing a process should clean registry tables" do
    if Robotem.registered?(TestProcess) do
      assert :ok = Robotem.delete_process(TestProcess)
    else
      assert {:ok, _pid} = Robotem.register_process(TestProcess, TestRunner)
      assert :ok = Robotem.delete_process(TestProcess)
    end
  end

  test "registering already registering process should give error" do
    if Robotem.registered?(TestProcess) do
      Robotem.delete_process(TestProcess)
    end

    assert {:ok, _pid} = Robotem.register_process(TestProcess, TestRunner)
    assert {:error, _} = Robotem.register_process(TestProcess, TestRunner)
  end

  test " registering a process and firing and event" do
    if not Robotem.registered?(Robotem.Test.TestProcess) do
      {:ok, pid} = Robotem.register_process(Robotem.Test.TestProcess, Robotem.Runner.Standard)
    end

    event = %Robotem.Test.Event.InvoiceAdded{
      amount: 100,
      date: DateTime.utc_now(),
      issued_to_id: "1234"
    }

    {:ok, seq} =
      Stream.append("teststream", event, 1)

    :timer.sleep(10000)
    assert 1 == 2
  end
end
