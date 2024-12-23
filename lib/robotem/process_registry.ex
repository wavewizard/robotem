defmodule Robotem.ProcessRegistry do
  @moduledoc """
  Distributed Process Registry using Mnesia
  """
  use Memento.Table,
    attributes: [:runner_pid, :process_module, :runner_module, :last_processed_no],
    type: :set

  @type info :: %{
          status: atom,
          last_processed: number,
          started_at: DateTime.t(),
          events_processed: number
        }
  def start(table_name) do
  end

  def register(runner_pid, process_module, runner_module) do
    Memento.transaction(fn ->
      Memento.Query.write(%Robotem.ProcessRegistry{
        runner_pid: runner_pid,
        process_module: process_module,
        runner_module: runner_module
      })
    end)
  end

  def clear_registry() do
    Memento.Table.clear(Robotem.ProcessRegistry)
  end

  def get_pid(process_module_name) do
    case Memento.transaction(fn ->
           Memento.Query.select(
             Robotem.ProcessRegistry,
             {:==, :process_module, process_module_name}
           )
         end) do
      {:ok, nil} -> nil
      {:ok, []} -> nil
      {:ok, [record]} -> record.runner_pid
    end
  end

  def get_process_module(pid) do
    case Memento.transaction(fn ->
           Memento.Query.select(
             Robotem.ProcessRegistry,
             {:==, :runner_pid, pid}
           )
         end) do
      {:ok, nil} -> nil
      {:ok, []} -> nil
      {:ok, [record]} -> {record.process_module, record.runner_module}
    end
  end

  def get_info(process_name) do
    case Memento.transaction(fn ->
           Memento.Query.select(
             Robotem.ProcessRegistry,
             {:==, :process_module, process_name}
           )
         end) do
      {:ok, nil} -> nil
      {:ok, []} -> nil
      {:ok, [record]} -> record
    end
  end

  def all() do
    {:ok, result} = Memento.transaction(fn -> Memento.Query.all(Robotem.ProcessRegistry) end)
    result
  end

  def remove(process_module) do
    Memento.transaction(fn ->
      {:ok, [record]} =
        Memento.transaction(fn ->
          Memento.Query.select(
            Robotem.ProcessRegistry,
            {:==, :process_module, process_module}
          )
        end)

      Memento.Query.delete_record(record)
    end)
  end

  def registered?(process_module) do
    case Memento.transaction(fn ->
           Memento.Query.select(
             Robotem.ProcessRegistry,
             {:==, :process_module, process_module}
           )
         end) do
      {:ok, nil} -> false
      {:ok, []} -> false
      {:ok, [_record]} -> true
    end
  end

  def can_register?(process_module) do
    not registered?(process_module)
  end
end
