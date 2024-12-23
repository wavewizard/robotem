defmodule Robotem.StatemRunner do
  @behaviour :gen_statem
  require Logger

  # lpen is last processed event no

  defstruct [:lpen]

  def callback_mode, do: [:state_functions, :state_enter]

  def start_link(args) do
    process_name = args[:process]
    :gen_statem.start_link(__MODULE__, args, name: process_name)
  end

  def init(args) do
    state = %{process: args[:process], tasks: %{}, lpen: args[:lpen]}
    # lpen = Keyword.fetch!(args, :lpen)
    # data = %__MODULE__{state: lpen}
    {:ok, :start_up, state, {:next_event, :internal, :load_batch}}
  end

  def start_up(:enter, _old_state, data) do
    Logger.info("Starting up")
    {:keep_state, data}
  end

  def start_up(:internal, :load_batch, data) do
    Logger.info("Checking last event")
    {:next_state, :idle, data}
  end

  def idle(:enter, _old_state, state) do
    Logger.info("Entered Idle State")
    {:keep_state, state}
  end

  def idle(:cast, :check_last_event, data) do
    IO.puts("This works like this")
    {:keep_state, data}
  end

  def idle(:cast, {:new_event, event, meta_data}, state) do
    IO.puts("#{inspect(event)}")

    envelop = event |> Map.put(:meta_data, meta_data)

    task =
      Task.Supervisor.async_nolink(Robotem.TaskSupervisor, fn ->
        state.process.handle_envelop(envelop)
      end)

    # store the task and event
    state = put_in(state.tasks[task.ref], meta_data.seq)
    {:keep_state, state}
  end

  def handle_common(:cast, {:check_last_event, some_val}, data) do
    IO.puts("Hello")
  end

  def handle_common(:crash, _state) do
    raise "Intentional crash"
  end

  def handle_common({ref, result}, state) do
    # result da taskin successful olup olmadigini gorebilirsin
    Process.demonitor(ref, [:flush])
    {event_no, state} = pop_in(state.tasks[ref])
    IO.puts("Task successfull #{event_no}")
    # TODO Burasi patlarsa controller da patliyor
    # badreturn girince test edebilirsin {:noreply, :ok, state}
    {:noreply, state}
  end

  def handle_common({:DOWN, ref, _, _, reason}, state) do
    {seq_no, state} = pop_in(state.tasks[ref])
    {:noreply, state}
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end
end
