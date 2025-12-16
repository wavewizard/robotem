defmodule RobotemTest do
  use ExUnit.Case
  alias Robotem
  alias Robotem.Test.TestProcess
  doctest Robotem

  setup do
    Memento.Table.create(Robotem.ProcessRegistry)
    {:ok, _pid} = Robotem.Controller.start_link([])
    :ok
  end

  test "register process" do
    if Robotem.registered?(TestProcess) do
      Robotem.delete_process(TestProcess)
    end

    assert {:ok, pid} = Robotem.register_process(TestProcess)
    # we should see process is registered with its name
    assert {TestProcess, %{runner: TestRunner}} = Robotem.ProcessRegistry.get_process_module(pid)
    # also we should see process id is registered in events registry
    assert TestProcess.interested() == Robotem.EventRegistry.get_events(pid)
  end

  test "removing a process should clean registry tables" do
    if Robotem.registered?(TestProcess) do
      assert :ok = Robotem.delete_process(TestProcess)
    else
      assert {:ok, _pid} = Robotem.register_process(TestProcess)
      assert :ok = Robotem.delete_process(TestProcess)
    end
  end

  test "registering already registering process should give error" do
    if Robotem.registered?(TestProcess) do
      Robotem.delete_process(TestProcess)
    end

    assert {:ok, _pid} = Robotem.register_process(TestProcess)
    assert {:error, _} = Robotem.register_process(TestProcess)
  end

  test " registering a process and firing and event" do
    if not Robotem.registered?(Robotem.Test.TestProcess) do
      {:ok, _pid} = Robotem.register_process(Robotem.Test.TestProcess)
    end

    event = %Robotem.Test.Event.InvoiceAdded{
      amount: 100,
      date: DateTime.utc_now(),
      issued_to_id: "1234"
    }

    # {:ok, _seq} =
    #   Stream.append("teststream", event, 1)

    :timer.sleep(10000)
    assert 1 == 2
  end
end
