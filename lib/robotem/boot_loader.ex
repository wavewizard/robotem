defmodule Robotem.BootLoader do
  alias Robotem.ProcessConfiguration
  require Logger

  def load_definitions_from_config() do
    Application.get_env(:robotem, :processes)
  end

  def create_tables() do
    Memento.Table.create!(Robotem.ProcessRegistry)
    Memento.Table.create!(Robotem.ProcessConfiguration)
  end

  def start() do
    maybe_add_new_processes()
  end

  @doc """
  Finds the newly defined process modules by comparing what is stored in ProcessConfiguration List and insert them to ProcessConfiguration
  """
  # def maybe_add_new_processes() do
  #   defs = Application.get_env(:robotem, :processes)

  #   def_processes =
  #     defs
  #     |> Enum.map(fn {k, v} ->
  #       {k, v.runner}
  #     end)

  #   diff = ProcessConfiguration.diff(def_processes)

  #   if Keyword.has_key?(diff, :ins) do
  #     # We will insert these, but these are just {k,v} so find the definitions
  #     new_processes = diff[:ins] |> Enum.map(fn {x, _y} -> x end)
  #     # we will get full definitions from defs
  #     Enum.reduce(defs, fn {module_name, info} ->
  #       if module_name in new_processes do
  #         p = %{
  #           process_module: module_name,
  #           runner_module: info.runner,
  #           process_type: {:source, :process}
  #         }

  #         Logger.info("Inserting New Process")
  #         ProcessConfiguration.add(p)
  #       end
  #     end)
  #   end
  # end
  def maybe_add_new_processes() do
    defs = Application.get_env(:robotem, :processes)

    def_processes =
      defs
      |> Enum.map(fn {k, v} ->
        {k, v.runner}
      end)

    diff = ProcessConfiguration.diff(def_processes)

    if Keyword.has_key?(diff, :ins) do
      # We will insert these, but these are just {k,v} so find the definitions
      new_processes = diff[:ins] |> Enum.map(fn {x, _y} -> x end)

      # Use Enum.each instead of Enum.reduce since we're not accumulating
      defs
      |> Enum.each(fn {module_name, info} ->
        if module_name in new_processes do
          p = %{
            process_module: module_name,
            runner_module: info.runner,
            process_type: {:source, :process}
          }

          Logger.info("Inserting New Process")
          ProcessConfiguration.add(p)
        end
      end)
    end
  end

  @doc """
  Check if the module available, if available returns list of available process
  else Log the processes is not available. We can also check additional properties
  of the process_module. ex: description defined? process_type defined or others
  """
  def check_modules(names) when is_list(names) do
    Enum.reduce(names, [], fn name, acc ->
      case Code.ensure_loaded(name) do
        {:module, module} ->
          [module | acc]

        {:error, _reason} ->
          IO.puts("Module #{name} does not exist.")
          acc
      end
    end)
    |> Enum.reverse()
  end

  def insert_new(process_list) do
    # all the processes defined in configuration are {:source, :process}

    Enum.each(process_list, fn process ->
      attrs = %{
        process_module: process.process_module,
        runner_module: process.runner_module,
        description: process.description,
        process_type: {:source, :process},
        code_exists?: true
      }

      ProcessConfiguration.add(attrs)
    end)
  end

  def start_processes() do
    {:ok, pid} = GenServer.start(Robotem.Controller, [])
    processes = ProcessConfiguration.all()

    Enum.each(processes, fn process ->
      GenServer.cast(pid, {:register, process.process_module})
    end)
  end

  def process_config() do
    configuration = load_definitions_from_config()

    configuration
    |> find_new_processes()
    |> insert_new_processes()

    # TODO There maybe deleted we are not going to run them and maybe tag them to delete 
  end

  def find_new_processes(configuration) do
    res =
      configuration
      |> Enum.map(fn {proc_module, v} -> {proc_module, v.runner} end)
      |> ProcessConfiguration.diff()

    if Keyword.has_key?(res, :ins) do
      process_modules =
        Keyword.get(res, :ins)
        |> Enum.map(fn {process_module, _} -> process_module end)

      Map.take(configuration, process_modules) |> Map.to_list()
    else
      []
    end
  end

  def insert_new_processes(process_list) when is_list(process_list) do
    Enum.each(process_list, fn {module_name, info} ->
      p = %{
        process_module: module_name,
        runner_module: info.runner,
        process_type: {:source, :process}
      }

      Logger.info("Inserting New Process")
      {:ok, _} = ProcessConfiguration.add(p)
    end)
  end
end
