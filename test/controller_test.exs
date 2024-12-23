defmodule ControllerTest do
  alias Robotem.ProcessRegistry
  alias TestRunner

  require Logger

  use ExUnit.Case

  setup do
    ProcessRegistry.clear_registry()
    Logger.configure(level: :debug)
    {:ok, ctrl_pid} = start_supervised({Robotem.Controller, []})
    {:ok, ctrl_pid: ctrl_pid}
  end

  test "test conductor start" do
    assert {:ok, pid} = TestRunner.start_link(TestProcess)
  end

  test "register process", %{ctrl_pid: pid} do
    process = Robotem.Test.TestProcess
    runner = Robotem.Runner.Standard

    assert {:ok, piddy} =
             GenServer.call(pid, {:register, process, runner})
  end

  test "remove proces", %{ctrl_pid: pid} do
    process = Robotem.Test.TestProcess
    runner = Robotem.Runner.Standard
    {:ok, piddy} = GenServer.call(pid, {:register, process, runner})
    :timer.sleep(100)
    assert :ok = GenServer.call(pid, {:remove, process})
  end

  test "Controller handles process crash and restart", %{ctrl_pid: pid} do
    process = Robotem.Test.TestProcess
    runner = Robotem.Runner.Standard

    # Register the process
    :ok = GenServer.cast(pid, {:register, process, runner})
    # Allow time for registration
    :timer.sleep(100)

    # Initial registration check
    old_pid = Robotem.ProcessRegistry.get_pid(process)
    assert is_pid(old_pid)

    # Crash the process
    GenServer.cast(old_pid, :crash)

    # Monitor the old process to wait for it to die
    ref = Process.monitor(old_pid)
    assert_receive {:DOWN, ^ref, :process, ^old_pid, _reason}, 5000

    :timer.sleep(100)
    # Verify old pid is removed from registry
    assert Robotem.ProcessRegistry.get_pid(process) != old_pid

    # Wait for the process to be restarted
    # Adjust sleep time as necessary
    :timer.sleep(500)

    # Verify new pid is registered

    new_pid = Robotem.ProcessRegistry.get_pid(process)
    assert is_pid(new_pid)
    assert new_pid != old_pid

    # Optional: Verify the new process is running correctly
    # GenServer.call(new_pid, :some_test_message)
    # assert ... # based on the expected response
  end
end
