defmodule Robotem.Dispatcher do
  use GenStage

  def start_link(args) do
    GenStage.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    state = []
    {:producer, state, dispatcher: GenStage.BroadcastDispatcher}
  end

  def handle_call({:notify, event}, _from, state) do
    # Dispatch immediately
    {:reply, :ok, [event], state}
  end

  def handle_demand(_demand, state) do
    # We don't care about the demand
    {:noreply, [], state}
  end
end
