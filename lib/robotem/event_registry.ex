defmodule Robotem.EventRegistry do
  @moduledoc """
  holds the event subscription of ProcessRunners in :ets_table,
  key: event_name value: list of pid of running process_runners
  """

  def start(table_name) do
    if :ets.whereis(table_name) == :undefined do
      :ets.new(table_name, [:bag, :public, :named_table])
    else
      {:error, "running"}
    end
  end

  def add(event_types, process_runner_pid) when is_atom(event_types) or is_list(event_types) do
    event_types =
      if is_atom(event_types) do
        [event_types]
      else
        event_types
      end

    if Enum.all?(event_types, &is_atom/1) do
      entries =
        Enum.map(event_types, fn event_type ->
          {event_type, process_runner_pid}
        end)

      case :ets.insert(:robotem_event_registry, entries) do
        true -> :ok
        false -> {:error, "Error inserting to events registry"}
      end
    else
      {:error, "All event types must be atoms"}
    end
  end

  def add_multi(table, events, runner_pid) do
    objects =
      for event <- events do
        {event, runner_pid}
      end

    :ets.insert(table, objects)
  end

  @doc """
  Removes the pid from event
  """

  def remove(pr_pid) do
    :ets.match_delete(:robotem_event_registry, {:"$1", pr_pid})
  end

  @doc """
  list registered runner pids under an event
  """

  def get_runners(event) do
    :ets.match(:robotem_event_registry, {event, :"$1"}) |> List.flatten()
  end

  def get_events(pr_pid) do
    :ets.match(:robotem_event_registry, {:"$1", pr_pid}) |> List.flatten()
  end

  def get_registered_events() do
    :ets.tab2list(:robotem_event_registry) |> Enum.map(fn {x, y} -> x end) |> List.flatten()
  end
end
