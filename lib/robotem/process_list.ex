defmodule Robotem.ProcessList do
  @moduledoc """
  Holds the process definitions.
  These are the processed that will be spawned.

  """
  use Memento.Table,
    attributes: [:process_module, :runner_module, :description, :opts],
    type: :set

  def add(process_module, runner_module, description) do
    result =
      Memento.transaction(fn ->
        case Memento.Query.read(__MODULE__, process_module) do
          %Robotem.ProcessList{} ->
            {:error, :already_exists}

          nil ->
            Memento.Query.write(%__MODULE__{
              process_module: process_module,
              runner_module: runner_module,
              description: description
            })
        end
      end)

    case result do
      {:ok, %Robotem.ProcessList{} = record} -> {:ok, record}
      {:ok, {:error, reason}} -> {:error, reason}
    end
  end

  def remove(process_module) do
    Memento.transaction(fn ->
      Memento.Query.delete_record(%Robotem.ProcessList{process_module: process_module})
    end)
  end

  def all() do
    {:ok, result} = Memento.transaction(fn -> Memento.Query.all(Robotem.ProcessList) end)
    result
  end

  def get(process_module) do
    {:ok, result} =
      Memento.transaction(fn -> Memento.Query.read(Robotem.ProcessList, process_module) end)

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
end
