defmodule Robotem.BootLoader.Test do
  use ExUnit.Case

  alias Robotem.BootLoader

  setup do
    Memento.stop()
    :ok = Memento.Schema.delete([node()])
    :ok = Memento.Schema.create([node()])
    Memento.start()
    :ok = Memento.Table.create(Robotem.ProcessConfiguration, disc_copies: [node()])
    :ok = Memento.Table.create(Robotem.ProcessRegistry)
    :ok = Memento.Table.clear(Robotem.ProcessRegistry)
    :ok
  end

  test "should read processes from config" do
    configured = Application.get_env(:robotem, :processes)
    assert ^configured = BootLoader.load_definitions_from_config()
  end

  test "maybe add new processes should insert new process to store if not exist" do
    _definitions = Application.get_env(:robotem, :processes)
    assert [] == Robotem.ProcessConfiguration.all()
    BootLoader.maybe_add_new_processes()
    :timer.sleep(100)
    assert 2 == Robotem.ProcessConfiguration.all() |> Enum.count()
  end

  test "compare should give eq, ins, dels" do
    BootLoader.start()

    conf_processes =
      Application.get_env(:robotem, :processes)

    assert Robotem.ProcessConfiguration.all() |> Enum.map(& &1.process_module)

    Robotem.BootLoader.start_processes()
    :timer.sleep(500)
    registered = Robotem.ProcessRegistry.all()
    IO.inspect(registered)

    assert Robotem.ProcessRegistry.all()
           |> Enum.any?(&(&1.process_module == Robotem.Test.TestProcess))
  end

  test "should return new processes" do
    conf = BootLoader.load_definitions_from_config()

    # lets register some processes
    {:ok, _} =
      Robotem.ProcessConfiguration.add(%{
        process_module: Test2,
        runner_module: :single,
        description: "Test4",
        process_type: {:source, :process}
      })

    {:ok, _} =
      Robotem.ProcessConfiguration.add(%{
        process_module: Test3,
        runner_module: :single,
        description: "Test5",
        process_type: {:source, :process}
      })

    assert [
             {Robotem.Test.TestProcess, %{runner: :single}},
             {Robotem.Test.TestProcess2, %{runner: :single}}
           ] == Robotem.BootLoader.find_new_processes(conf)
  end

  test "should insert new processes to configuraiton" do
    {:ok, _} =
      Robotem.ProcessConfiguration.add(%{
        process_module: Test3,
        runner_module: :single,
        description: "Test5",
        process_type: {:source, :process}
      })

    assert :ok == BootLoader.process_config()
    # and we should see two newly defined process
    assert Robotem.ProcessConfiguration.all() |> Enum.count() == 3
  end
end
