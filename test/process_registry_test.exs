defmodule ProcessRegistryTest do
  alias Robotem.ProcessRegistry
  use ExUnit.Case

  setup do
    Memento.Table.create(ProcessRegistry)
    Memento.Table.clear(ProcessRegistry)
    :ok
  end

  test "register" do
  end

  test "get_info should return the info" do
    {:ok, %ProcessRegistry{process_module: TestProcess}} =
      ProcessRegistry.register(self(), TestProcess, TestRunner)

    assert %Robotem.ProcessRegistry{} = ProcessRegistry.get_info(TestProcess)
  end

  test "when given a pid get_process_module should return process_module" do
    {:ok, _process_reg} = ProcessRegistry.register(self(), TestProcess, TestRunner)
    :timer.sleep(200)
    assert ProcessRegistry.get_process_module(self()) == {TestProcess, TestRunner}
  end

  test " get_pid() should return pid when given process module" do
    {:ok, _process_reg} = ProcessRegistry.register(self(), TestProcess, TestRunner)
    :timer.sleep(200)
    assert ProcessRegistry.get_pid(TestProcess) == self()
  end

  test " when given process_module to get_info should return ProcessRegistry struct" do
    {:ok, _process_reg} = ProcessRegistry.register(self(), TestProcess, TestRunner)

    self_pid = self()

    assert %ProcessRegistry{process_module: TestProcess, runner_pid: ^self_pid} =
             ProcessRegistry.get_info(TestProcess)
  end

  test "clear registry should clear all registries" do
    {:ok, _process_reg} = ProcessRegistry.register(self(), TestProcess, TestRunner)

    assert :ok == ProcessRegistry.clear_registry()
    assert [] == ProcessRegistry.all()
  end

  test "get_all() should return all the registered processes" do
    # Spawn a process and register two processes
    proc_pid = Process.spawn(fn -> :ok end, [])
    {:ok, _process_reg1} = ProcessRegistry.register(self(), TestProcess, TestRunner)
    {:ok, _process_reg2} = ProcessRegistry.register(proc_pid, TestProcess2, TestRunner)

    :timer.sleep(200)
    self_pid = self()

    # Define the expected ProcessRegistry structs with all fields
    expected = [
      %ProcessRegistry{
        process_module: TestProcess,
        runner_module: TestRunner,
        runner_pid: self_pid,
        __meta__: Memento.Table,
        last_processed_no: nil
      },
      %ProcessRegistry{
        process_module: TestProcess2,
        runner_module: TestRunner,
        runner_pid: proc_pid,
        __meta__: Memento.Table,
        last_processed_no: nil
      }
    ]

    # Get the actual list of registered processes
    actual = ProcessRegistry.all()

    # Sort both lists based on process_module for comparison
    sorted_expected = Enum.sort(expected, fn a, b -> a.process_module <= b.process_module end)
    sorted_actual = Enum.sort(actual, fn a, b -> a.process_module <= b.process_module end)

    # Assert that the sorted lists match
    assert sorted_expected == sorted_actual
  end

  test "unregister() should remove the registered process" do
    {:ok, _process_reg} = ProcessRegistry.register(self(), TestProcess, TestRunner)

    assert :ok = ProcessRegistry.unregister(TestProcess)
    assert nil == ProcessRegistry.get_pid(TestProcess)
  end

  test "registered? should return true if process is registred" do
    ProcessRegistry.register(self(), TestProcess, TestRunner)
    assert ProcessRegistry.registered?(TestProcess)
  end

  test "registered? should return false if process is no registred" do
    # ProcessRegistry.register(self(), TestProcess, TestRunner)
    refute ProcessRegistry.registered?(TestProcess)
  end

  test "can_register? should return true if process_module is not registred" do
    assert true = ProcessRegistry.can_register?(TestProcess)
  end

  test "can_register? should return false if process_module already registred" do
    ProcessRegistry.register(self(), TestProcess, TestRunner)

    refute ProcessRegistry.can_register?(TestProcess)
  end
end
