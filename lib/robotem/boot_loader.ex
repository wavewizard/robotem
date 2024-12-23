defmodule Robotem.BootLoader do
  alias Robotem.ProcessList

  def load_definitions_from_config() do
    Application.get_env(:robotem, :processes)
    |> Enum.flat_map(fn {_g, p} -> Map.to_list(p) end)
    |> Enum.map(fn {k, v} -> {k, v.runner} end)
  end

  def create_tables() do
    Memento.Table.create!(Robotem.ProcessRegistry)
    Memento.Table.create!(Robotem.ProcessList)
  end

  def start() do
    definitions = load_definitions_from_config()

    res = ProcessList.diff(definitions)

    if Keyword.has_key?(res, :ins) do
      insert_newly_defined(Keyword.fetch!(res, :ins))
    end
  end

  def insert_newly_defined(process_list) do
    Enum.each(process_list, &ProcessList.add(elem(&1, 0), elem(&1, 1), ""))
  end

  def start_processes() do
    {:ok, pid} = GenServer.start(Robotem.Controller, [])
    processes = ProcessList.all()

    Enum.each(processes, fn process ->
      GenServer.cast(pid, {:register, process.process_module, process.runner_module})
    end)
  end
end
