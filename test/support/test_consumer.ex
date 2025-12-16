defmodule TestConsumer do
  use GenStage

  def start_link(_) do
    GenStage.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    {:consumer, [], subscribe_to: [{Robotem.Sorter, max_demand: 1}]}
  end

  def handle_events(events, _from, state) do
    IO.puts("Hello Sandiego")
    {:noreply, [], state ++ events}
  end

  def handle_call(:get_events, _from, state) do
    {:reply, state, [], []}
  end
end
