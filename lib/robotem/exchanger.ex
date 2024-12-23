defmodule Robotem.Exchanger do
  @moduledoc """
  Listens a publisher, maps incoming messages via assigned mapper,
  and sends transformed events to subscribers.
  """
  alias Robotem.EventRegistry
  require Logger
  use GenStage

  defstruct [:mapper]

  def start_link(args) do
    GenStage.start_link(Robotem.Exchanger, args)
  end

  def init(args) do
    # This will subscribe to eventos.publisher
    # TODO, implement connection instead dependency

    state = %{mapper: args[:mapper]}
    {:consumer, state, [subscribe_to: [Eventos.Publisher]]}
  end

  def handle_events(events, _from, state) do
    # We will look at the registered evens and fire them
    # events = EventRegistry.get_runners(events |> List.first())
    Logger.info("#{__MODULE__} received event is #{inspect(events)}")

    events
    |> Enum.each(fn event_record ->
      # I need get the event_type from the event record, or from the envelop
      # Then I will pass it to subscribing processes.
      {:ok, event, meta_data} = state.mapper.map(event_record)
      handle_event(event, meta_data)
    end)

    {:noreply, [], state}
  end

  defp handle_event(event, meta_data) do
    case EventRegistry.get_runners(event.event_type) do
      [] ->
        registered_events =
          EventRegistry.get_registered_events() |> Enum.map(fn x -> inspect(x) end)

        Logger.alert("ignoring  #{event.event_type}. Not registred }")

        :ok

      pids when is_list(pids) ->
        pids |> Enum.each(fn pid -> GenServer.cast(pid, {:new_event, event, meta_data}) end)
    end
  end
end
