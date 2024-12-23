defmodule Robotem.BootLoader.Test do
  use ExUnit.Case

  alias Robotem.BootLoader

  setup do
    Memento.stop()
    :ok = Memento.Schema.delete([node()])
    :ok = Memento.Schema.create([node()])
    Memento.start()
    :ok = Memento.Table.create(Robotem.ProcessList, disc_copies: [node()])
    :ok = Memento.Table.create(Robotem.ProcessRegistry)
    :ok = Memento.Table.clear(Robotem.ProcessRegistry)
    :ok
  end

  test "should read processes from config" do
    assert [] == BootLoader.load_definitions_from_config()
  end

  test "compare should give eq, ins, dels" do
    BootLoader.start()

    conf_processes =
      Application.get_env(:robotem, :processes)
      |> Enum.flat_map(fn {_g, p} -> Map.to_list(p) end)
      |> Enum.map(fn {k, _v} -> k end)

    stored_processes = assert Robotem.ProcessList.all() |> Enum.map(& &1.process_module)
    missing = conf_processes -- stored_processes
    assert Enum.empty?(missing)

    Robotem.BootLoader.start_processes()
    :timer.sleep(500)

    assert Robotem.ProcessRegistry.all()
           |> Enum.any?(&(&1.process_module == Robotem.Test.TestProcess))
  end
end
