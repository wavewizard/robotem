defmodule TestGenerator do
  use GenStage

  def start_link(_args) do
  end

  def init(_args) do
    state = []
    {:producer, state}
  end

  def handle_demand(demand, state) when demand > 0 do
    # Basically state is holding the events and when new events arrive
    # it will give the number of demand from the events
    reversed = state |> Enum.reverse()
    events = reversed |> Enum.take(demand)
    buffer = reversed |> Enum.drop(demand) |> Enum.reverse()
    {:noreply, events, buffer}
  end

  def handle_cast({:pust_event, event}, state) do
    events = [event | state]
    {:reply, :ok, events}
  end
end
