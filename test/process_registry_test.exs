defmodule ProcessRegistryTest do
  alias Robotem.ProcessRegistry
  use ExUnit.Case

  test "start process_registry table" do
    assert :test_table = ProcessRegistry.start(:test_table)
  end

  test "add" do
    pid = spawn(fn -> 1 + 2 end)

    assert {:ok, %Robotem.ProcessRegistry{process_module: TestProcess}} =
             ProcessRegistry.register(pid, TestProcess, TestRunner)
  end

  test "get_pid should return nil if no process registered" do
    ProcessRegistry.start(:test_table)

    assert nil == ProcessRegistry.get_pid(:nope)
  end

  test "get_info should return the info" do
    pid = spawn(fn -> 1 + 2 end)
    ProcessRegistry.register(pid, TestProcess, TestRunner)

    assert %Robotem.ProcessRegistry{} = ProcessRegistry.get_info(TestProcess)
  end

  test "get robotem process" do
    pid = spawn(fn -> 1 + 2 end)
    ProcessRegistry.register(pid, TestProcess, TestRunner)

    pid = ProcessRegistry.get_pid(TestProcess)
    :timer.sleep(100)
    assert {TestProcess, TestRunner} == ProcessRegistry.get_process_module(pid)
  end

  test "registered?" do
    pid = spawn(fn -> 1 + 2 end)
    ProcessRegistry.register(pid, TestProcess, TestRunner)
    assert ProcessRegistry.registered?(TestProcess)
  end

  test "can_register?" do
    pid = spawn(fn -> 1 + 2 end)
    ProcessRegistry.register(pid, TestProcess, TestRunner)

    assert false == ProcessRegistry.can_register?(TestProcess)
  end
end
