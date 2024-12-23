defmodule Robotem.Runner.Standard do
  use GenServer
  require Logger

  @type state :: :syncing | :processing | :idle

  defstruct [
    :last_event_seq,
    :process_module,
    :tasks,
    :buffer,
    :dlq,
    :refs,
    :max_attempts,
    :state
  ]

  def start_link(args) do
    process_module = args[:process_module]
    GenServer.start_link(__MODULE__, args, name: process_module)
  end

  def init(args) do
    state = %__MODULE__{
      process_module: args[:process_module],
      tasks: %{},
      dlq: %{},
      refs: %{},
      max_attempts: 3,
      buffer: [],
      last_event_seq: args[:last_event_seq],
      state: :idle
    }

    {:ok, state}
  end

  def handle_cast({:new_event, event, meta}, state) do
    task =
      Task.Supervisor.async_nolink(Robotem.TaskSupervisor, fn ->
        process_event(event, meta, state.process_module)
      end)

    ref = task.ref

    Logger.info("#task started for #{event.event_type}, ref = #{inspect(task.ref)}")

    tasks = Map.put(state.tasks, meta.seq, %{attempt: 1, ref: ref, event: event, meta: meta})
    refs = Map.put(state.refs, ref, meta.seq)
    {:noreply, %{state | tasks: tasks, refs: refs}}
  end

  def handle_cast(:crash, _state) do
    raise "Intentional crash"
  end

  def handle_info({ref, {:ok, _result}}, state) do
    Process.demonitor(ref)
    event_id = Map.get(state.refs, ref)
    tasks = Map.delete(state.tasks, event_id)
    refs = Map.delete(state.refs, ref)
    {:noreply, %{state | tasks: tasks, refs: refs}}
  end

  def handle_info({ref, {:error, reason}}, state) do
    Logger.alert("task failed #{inspect(reason)}")
    event_id = Map.get(state.refs, ref)
    handle_task_failure(event_id, state)
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) do
    Process.demonitor(ref)

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    event_id = Map.get(state.refs, ref)
    handle_task_failure(event_id, state)
  end

  def handle_info({:retry, event_id, event, meta, attempt}, state) do
    Logger.info("Retrying task for event_id, attempt = #{attempt}")

    task =
      Task.Supervisor.async_nolink(Robotem.TaskSupervisor, fn ->
        process_event(event, meta, state.process_module)
      end)

    ref = task.ref

    tasks =
      Map.put(state.tasks, event_id, %{attempt: attempt, ref: ref, event: event, meta: meta})

    refs = Map.put(state.refs, ref, event_id)

    {:noreply, %{state | tasks: tasks, refs: refs}}
  end

  defp handle_task_failure(event_id, state) do
    task_data = Map.get(state.tasks, event_id)

    case task_data do
      %{attempt: attempt, event: event, meta: meta} when attempt < state.max_attempts ->
        # milliseconds
        delay = (:math.pow(2, attempt) * 1000) |> trunc()
        Process.send_after(self(), {:retry, event_id, event, meta, attempt + 1}, delay)
        {:noreply, state}

      %{event: event, meta: meta} ->
        dlq = Map.put(state.dlq, meta.seq, event)
        tasks = Map.delete(state.tasks, event_id)
        refs = Map.delete(state.refs, task_data.ref)
        {:noreply, %{state | tasks: tasks, refs: refs, dlq: dlq}}
    end
  end

  defp process_event(event, meta, module) do
    module.handle_envelop(event, meta)
  end
end
