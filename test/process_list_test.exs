defmodule ProcessList.Test do
  use ExUnit.Case

  alias Robotem.ProcessList

  setup do
    Memento.stop()
    :ok = Memento.Schema.delete([node()])
    :ok = Memento.Schema.create([node()])
    Memento.start()
    :ok = Memento.Table.create(Robotem.ProcessList, disc_copies: [node()])
    :ok
  end

  test "add process definition to list" do
    process_module = Robotem.Test.TestProcess
    runner_module = Robotem.Runner
    description = "Test Process"
    assert {:ok, record} = ProcessList.add(process_module, runner_module, description)
  end

  test "should give {:error, :already_exists} when process exists" do
    process_module = Robotem.Test.TestProcess
    runner_module = Robotem.Runner
    description = "Test Process"
    assert {:ok, record} = ProcessList.add(process_module, runner_module, description)

    assert {:error, :already_exists} = ProcessList.add(process_module, runner_module, description)
  end

  test "should remove process" do
    process_module = Robotem.Test.TestProcess
    runner_module = Robotem.Runner
    description = "Test Process"

    assert {:ok, record} = ProcessList.add(process_module, runner_module, description)
    :timer.sleep(10)
    assert :ok = ProcessList.remove(process_module)
  end

  test "should get all the records" do
    process1_module = Robotem.Test.TestProcess
    runner1_module = Robotem.Runner
    description = "Test Process"

    assert {:ok, record} = ProcessList.add(process1_module, runner1_module, description)

    process2_module = Robotem.Test.TestProcessX
    runner2_module = Robotem.Runner
    description = "Test ProcessX"

    assert {:ok, record2} = ProcessList.add(process2_module, runner2_module, description)

    assert [
             %Robotem.ProcessList{process_module: process1_module},
             %Robotem.ProcessList{process_module: process2_module}
           ] = Robotem.ProcessList.all()
  end

  test "get should get the record of registered process module" do
    process1_module = Robotem.Test.TestProcess
    runner1_module = Robotem.Runner
    description = "Test Process"

    assert {:ok, record} = ProcessList.add(process1_module, runner1_module, description)
    assert Robotem.ProcessList.get(process1_module) == record
  end

  test "diff should give {new, remove} list" do
    conf = [
      {TestProcess, DefaultRunner},
      {TestProcess3, DefaultRunner},
      {TestPocess4, DefaultRunner}
    ]

    ProcessList.add(TestProcess, DefaultRunner, "")
    ProcessList.add(TestProcess2, DefaultRunner, "")
    ProcessList.add(TestProcess3, DefaultRunner, "")

    expected = [
      eq: [{TestProcess, DefaultRunner}, {TestProcess3, DefaultRunner}],
      del: [{TestProcess2, DefaultRunner}],
      ins: [{TestPocess4, DefaultRunner}]
    ]

    assert expected == Robotem.ProcessList.diff(conf)
  end
end
