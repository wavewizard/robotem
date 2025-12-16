defmodule ControllerTest do
  alias Robotem.ProcessRegistry
  alias TestRunner

  require Logger

  use ExUnit.Case, async: false

  setup do
    ProcessRegistry.clear_registry()

    Logger.configure(level: :debug)
    {:ok, ctrl_pid} = start_supervised({Robotem.Controller, []})

    on_exit(fn ->
      # Clean up any running processes
      # Stop the controller if necessary
      # Clear process configurations and registry

      ProcessRegistry.clear_registry()
      # Optionally, stop the controller if not managed by supervisor
      # Supervisor.terminate_child(Supervisor, ctrl_pid)
    end)

    {:ok, ctrl_pid: ctrl_pid}
  end

  # test "test Controller start" do
  #   assert {:ok, pid} = Robotem.Runner.Standard.start_link(process_module: TestProcess)
  # end

  test "register process", %{ctrl_pid: pid} do
    process_module = Robotem.Test.TestProcess
    # add process to configuration first

    Robotem.ProcessConfiguration.add(%{
      process_module: process_module,
      runner_module: :single,
      description: "Test Process",
      process_type: {:source, :process}
    })

    assert :ok = GenServer.cast(pid, {:register, process_module})
    :timer.sleep(1000)
  end

  test "remove proces", %{ctrl_pid: pid} do
    process_module = Robotem.Test.TestProcess

    Robotem.ProcessConfiguration.add(%{
      process_module: process_module,
      runner_module: :single,
      description: "Test Process",
      process_type: {:source, :process}
    })

    assert :ok = GenServer.cast(pid, {:register, process_module})
    :timer.sleep(100)
    assert :ok = GenServer.cast(pid, {:remove, process_module})
    # TODO Ensure process not exists in registry anymore
  end

  test "Controller handles process crash and restart", %{ctrl_pid: pid} do
    process_module = Robotem.Test.TestProcess

    Robotem.ProcessConfiguration.add(%{
      process_module: process_module,
      runner_module: :single,
      description: "Test Process",
      process_type: {:source, :process}
    })

    assert :ok = GenServer.cast(pid, {:register, process_module})
    # Allow time for registration
    :timer.sleep(100)

    # Initial registration check
    old_pid = Robotem.ProcessRegistry.get_pid(process_module)
    assert is_pid(old_pid)

    # Crash the process
    GenServer.cast(old_pid, :crash)

    # Monitor the old process to wait for it to die
    ref = Process.monitor(old_pid)
    assert_receive {:DOWN, ^ref, :process, ^old_pid, _reason}, 5000

    :timer.sleep(100)
    # Verify old pid is removed from registry
    assert Robotem.ProcessRegistry.get_pid(process_module) != old_pid

    # Wait for the process to be restarted
    # Adjust sleep time as necessary
    :timer.sleep(500)

    # Verify new pid is registered

    new_pid = Robotem.ProcessRegistry.get_pid(process_module)
    assert is_pid(new_pid)
    assert new_pid != old_pid

    # Optional: Verify the new process is running correctly
    # GenServer.call(new_pid, :some_test_message)
    # assert ... # based on the expected response
  end
end
