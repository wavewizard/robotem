defmodule ProcessList.Test do
  use ExUnit.Case

  alias Robotem.ProcessConfiguration

  setup do
    Memento.stop()
    :ok = Memento.Schema.delete([node()])
    :ok = Memento.Schema.create([node()])
    Memento.start()
    :ok = Memento.Table.create(Robotem.ProcessConfiguration, disc_copies: [node()])
    :ok
  end

  test "add process definition to list" do
    process_module = Robotem.Test.TestProcess
    runner_module = Robotem.Runner
    process_type = {:source, :process}
    description = "Test Process"

    assert {:ok, _record} =
             ProcessConfiguration.add(process_module, runner_module, description, process_type)
  end

  test "should give {:error, :already_exists} when process exists" do
    process_module = Robotem.Test.TestProcess
    runner_module = Robotem.Runner
    description = "Test Process"
    process_type = {:source, :process}

    assert {:ok, _record} =
             ProcessConfiguration.add(process_module, runner_module, description, process_type)

    assert {:error, :already_exists} =
             ProcessConfiguration.add(process_module, runner_module, description, process_type)
  end

  test "ensure process configuration fields are registered correctly" do
    process_module = Robotem.Test.TestProcess
    runner_module = Robotem.Runner
    process_type = {:source, :process}
    description = "Test Process"

    attrs = %{
      process_module: process_module,
      runner_module: runner_module,
      description: description,
      process_type: process_type,
      last_seen: 0,
      concurrency: 1
    }

    assert {:ok, record} =
             ProcessConfiguration.add(attrs)

    expected_record = %Robotem.ProcessConfiguration{
      process_module: process_module,
      runner_module: runner_module,
      description: description,
      process_type: process_type,
      last_seen: 0,
      concurrency: 1,
      code_exists?: true
    }

    assert record == expected_record
  end

  test "should remove process" do
    process_module = Robotem.Test.TestProcess
    runner_module = Robotem.Runner
    description = "Test Process"
    process_type = {:source, :process}

    assert {:ok, _record} =
             ProcessConfiguration.add(process_module, runner_module, description, process_type)

    :timer.sleep(10)
    assert :ok = ProcessConfiguration.remove(process_module)
  end

  test "should get all the records" do
    process1_module = Robotem.Test.TestProcess
    runner1_module = Robotem.Runner
    description = "Test Process"
    process_type = {:source, :process}

    assert {:ok, _record} =
             ProcessConfiguration.add(process1_module, runner1_module, description, process_type)

    process2_module = Robotem.Test.TestProcessX
    runner2_module = Robotem.Runner
    description = "Test ProcessX"
    process2_type = {:source, :process}

    assert {:ok, _record2} =
             ProcessConfiguration.add(process2_module, runner2_module, description, process2_type)

    assert [
             %Robotem.ProcessConfiguration{process_module: ^process1_module},
             %Robotem.ProcessConfiguration{process_module: ^process2_module}
           ] = Robotem.ProcessConfiguration.all()
  end

  test "get should get the record of registered process module" do
    process1_module = Robotem.Test.TestProcess
    runner1_module = Robotem.Runner
    description = "Test Process"
    process_type = {:source, :process}

    assert {:ok, record} =
             ProcessConfiguration.add(
               process1_module,
               runner1_module,
               description,
               process_type
             )

    assert Robotem.ProcessConfiguration.get(process1_module) == record
  end

  test "diff should give {new, remove} list" do
    conf = [
      {TestProcess, DefaultRunner},
      {TestProcess3, DefaultRunner},
      {TestPocess4, DefaultRunner}
    ]

    ProcessConfiguration.add(TestProcess, DefaultRunner, "Test Description", {:source, :process})
    ProcessConfiguration.add(TestProcess2, DefaultRunner, "Test Description", {:source, :process})
    ProcessConfiguration.add(TestProcess3, DefaultRunner, "Test Description", {:source, :process})

    expected = [
      eq: [{TestProcess, DefaultRunner}, {TestProcess3, DefaultRunner}],
      del: [{TestProcess2, DefaultRunner}],
      ins: [{TestPocess4, DefaultRunner}]
    ]

    assert expected == Robotem.ProcessConfiguration.diff(conf)
  end

  test "set code_not_exists should tag process code_not_exits" do
    process_module = Robotem.Test.TestProcess
    runner_module = Robotem.Runner
    description = "Test Process"
    process_type = {:source, :process}

    assert {:ok, _record} =
             ProcessConfiguration.add(process_module, runner_module, description, process_type)

    :timer.sleep(10)

    assert {:ok, %ProcessConfiguration{code_exists?: false}} =
             ProcessConfiguration.set_not_exists(process_module)
  end

  test "update last seen should update the last_seen seq no" do
    process_module = Robotem.Test.TestProcess
    runner_module = Robotem.Runner
    process_type = {:source, :process}
    description = "Test Process"

    attrs = %{
      process_module: process_module,
      runner_module: runner_module,
      description: description,
      process_type: process_type,
      last_seen: 0,
      concurrency: 1
    }

    assert {:ok, _record} =
             ProcessConfiguration.add(attrs)

    assert :ok = ProcessConfiguration.update_last_seen(process_module, 10)
    assert %ProcessConfiguration{last_seen: 10} = ProcessConfiguration.get(process_module)
  end

  test "get_runnable should return runnable processes" do
    process_module = Robotem.Test.TestProcess
    runner_module = Robotem.Runner
    description = "Test Process"
    process_type = {:source, :process}

    assert {:ok, r1} =
             ProcessConfiguration.add(process_module, runner_module, description, process_type)

    assert {:ok, r2} =
             ProcessConfiguration.add(TestProcess2, runner_module, description, process_type)

    assert {:ok, _f} = ProcessConfiguration.set_not_exists(r2.process_module)

    assert [r1] == ProcessConfiguration.get_runnable_processes()
  end
end
