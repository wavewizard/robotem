defmodule Robotem.ProcessConfiguration do
  @moduledoc """
  Holds the process definitions.

  """

  use Memento.Table,
    attributes: [
      :process_module,
      :runner_module,
      :description,
      :last_seen,
      :concurrency,
      :process_type,
      :code_exists?
    ],
    type: :set

  def add(process_module, runner_module, description, process_type, opts \\ []) do
    opts = Keyword.merge([last_seen: 0, concurrency: 1], opts)

    add(%{
      process_module: process_module,
      runner_module: runner_module,
      description: description,
      last_seen: Keyword.get(opts, :last_seen),
      concurrency: Keyword.get(opts, :concurrency),
      process_type: process_type,
      code_exists?: true
    })
  end

  def add(attrs) do
    required_keys = [:process_module, :runner_module, :process_type]
    missing_keys = required_keys -- Map.keys(attrs)

    if missing_keys != [] do
      {:error, "Missing required keys: #{inspect(missing_keys)}"}
    else
      Memento.transaction(fn ->
        case Memento.Query.read(__MODULE__, attrs[:process_module]) do
          %Robotem.ProcessConfiguration{} ->
            {:error, :already_exists}

          nil ->
            process_config = struct!(__MODULE__, attrs)

            case Memento.Query.write(process_config) do
              %__MODULE__{} = record -> {:ok, record}
              _ -> {:error, :no_write}
            end
        end
      end)
      |> case do
        {:ok, {:error, :already_exists}} -> {:error, :already_exists}
        {:ok, {:ok, record}} -> {:ok, record}
        {:ok, {:error, reason}} -> {:error, reason}
      end
    end
  end

  def set_not_exists(process_module) do
    Memento.transaction(fn ->
      process = Memento.Query.read(Robotem.ProcessConfiguration, process_module)
      new_process = %{process | code_exists?: false}
      Memento.Query.write(new_process)
    end)
  end

  def remove(process_module) do
    Memento.transaction(fn ->
      Memento.Query.delete_record(%Robotem.ProcessConfiguration{process_module: process_module})
    end)
  end

  def all() do
    {:ok, result} = Memento.transaction(fn -> Memento.Query.all(Robotem.ProcessConfiguration) end)
    result
  end

  def get_runnable_processes() do
    {:ok, result} =
      Memento.transaction(fn ->
        Memento.Query.select(Robotem.ProcessConfiguration, [{:==, :code_exists?, true}])
      end)

    result
  end

  def get(process_module) do
    {:ok, result} =
      Memento.transaction(fn ->
        Memento.Query.read(Robotem.ProcessConfiguration, process_module)
      end)

    result
  end

  @doc """
  Compares the given list of process definitions with the stored processes, outputs
  a tuple. first element of tuple is the processes that are not stored, which needs to be added
  second element of the tuple are stored but not in the provided process list 
  """
  def diff(process_definitions) do
    records = all() |> Enum.map(fn p -> {p.process_module, p.runner_module} end)

    List.myers_difference(records, process_definitions)
  end

  def update_last_seen(process_module, seq_no) do
    case Memento.transaction(fn ->
           rec = Memento.Query.read(__MODULE__, process_module)

           updated = %{rec | last_seen: seq_no}
           Memento.Query.write(updated)
         end) do
      {:ok, _record} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
