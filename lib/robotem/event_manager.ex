defmodule Robotem.EventManager do
  use GenServer
  require Logger

  @subscriptions_table :subscriptions

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    :ets.new(@subscriptions_table, [:set, :protected, :named_table])
    {:ok, %{}}
  end

  def handle_call({:subscribe, pid, event_type}, _from, state) do
    true = :ets.insert(@subscriptions_table, {event_type, pid})
    Process.monitor(pid)
    {:reply, :ok, state}
  end

  def handle_call({:unsubscribe, pid, event_type}, _from, state) do
    :ets.match_delete(@subscriptions_table, {event_type, pid})
    {:reply, :ok, state}
  end

  def handle_cast({:publish, event_type, event_data}, state) do
    case :ets.lookup(@subscriptions_table, event_type) do
      [] ->
        Logger.debug("No subscribers for event type #{inspect(event_type)}")

      subscribers ->
        Enum.each(subscribers, fn {^event_type, subscriber_pid} ->
          send(subscriber_pid, {:event, event_type, event_data})
        end)
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove pid from all event_type lists
    case :ets.select(@subscriptions_table, [{{:"$1", pid}, [], [:"$1"]}]) do
      [] ->
        :ok

      event_types ->
        Enum.each(event_types, fn event_type ->
          :ets.delete(@subscriptions_table, {event_type, pid})
        end)
    end

    {:noreply, state}
  end

  def subscribe(pid, event_type) do
    GenServer.call(__MODULE__, {:subscribe, pid, event_type})
  end

  def unsubscribe(pid, event_type) do
    GenServer.call(__MODULE__, {:unsubscribe, pid, event_type})
  end

  def publish(event_type, event_data) do
    GenServer.cast(__MODULE__, {:publish, event_type, event_data})
  end
end
