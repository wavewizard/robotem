defmodule Robotem.Runner.Single do
  @moduledoc """
  The `Robotem.Runner.Standard` module is a GenServer responsible for managing the processing of events in the Robotem system. It handles the execution of tasks, retries for failed tasks, and maintains a dead-letter queue (DLQ) for tasks that cannot be processed successfully.

  This runner manages the lifecycle of tasks, ensuring that each event is processed correctly and that failures are handled gracefully. It supports retry mechanisms for failed tasks and keeps track of the last seen event sequence to maintain processing continuity.

  ## Overview

  - **Task Management**: Starts and monitors tasks for processing events.
  - **Retry Mechanism**: Retries failed tasks with exponential backoff.
  - **Dead-Letter Queue (DLQ)**: Stores events that could not be processed after maximum retry attempts.
  - **State Management**: Tracks the state of the runner (syncing, processing, idle).

  ## States

  The runner can be in one of the following states:

  - `:syncing`: The runner is synchronizing with the event source.
  - `:processing`: The runner is actively processing events.
  - `:idle`: The runner is idle, waiting for new events.

  ## Data Structures

  - `tasks`: A map tracking currently processing tasks.
  - `refs`: A map associating task references with event IDs.
  - `dlq`: A map storing events that could not be processed.

  ## Dependencies

  - `Robotem.ProcessConfiguration`: Used for updating the last seen event sequence.
  - `Robotem.TaskSupervisor`: Manages the task supervision tree.

  """
  use GenServer
  require Logger

  alias Robotem.ProcessConfiguration

  @type state :: :syncing | :processing | :idle

  @retry_delay_base 200
  defstruct [
    :last_seen,
    :process_module,
    :tasks,
    :buffer,
    :dlq,
    :refs,
    :max_attempts,
    :state
  ]

  def start_link(args) do
    # process_module = args[:process_module]
    GenServer.start_link(__MODULE__, args, name: args.process_module)
  end

  @impl GenServer
  def init(args) do
    state = %__MODULE__{
      process_module: args.process_module,
      tasks: %{},
      dlq: %{},
      refs: %{},
      max_attempts: 3,
      buffer: [],
      last_seen: args.last_seen,
      state: :idle
    }

    {:ok, state}
  end

  @doc """
  Handles the casting of new events to be processed.

  ## Parameters

    - `{:new_event, event, meta}`: A new event to be processed.
      - `event`: The event data.
      - `meta`: Metadata associated with the event, including `:seq` and `:timestamp`.

  ## Callbacks

    - Starts a new task to process the event.
    - Updates the last seen sequence number.
    - Tracks the task in the `tasks` and `refs` maps.

  """
  @impl GenServer
  def handle_cast({:new_event, event}, state) do
    # However before processing a new event, we should check the last_seen event for this
    # process. If there is a gap between incoming event seq_no  and last_seen we need to
    # run synchronization to stay up to date.
    # We can run sync as a separate task and go into syncing mode. While in syncing mode
    # new events arrived to process can be buffered and once the syncing completes(We can spawn separate syncing task, tag it. when it completes we can return to insync state!)

    Task.start(fn ->
      ProcessConfiguration.update_last_seen(state.process_module, event.seq)
    end)

    task =
      Task.Supervisor.async_nolink(Robotem.TaskSupervisor, fn ->
        process_event(event, state.process_module)
      end)

    ref = task.ref

    Logger.info("#task started for #{event.event_type}, ref = #{inspect(task.ref)}")

    tasks = Map.put(state.tasks, event.seq, %{attempt: 1, ref: ref, event: event})
    refs = Map.put(state.refs, ref, event.seq)
    {:noreply, %{state | tasks: tasks, refs: refs, last_seen: event.seq}}
  end

  def handle_cast(:crash, _state) do
    raise "Intentional crash"
  end

  @impl GenServer
  def handle_info({ref, {:ok, _result}}, state) do
    handle_task_success(ref, state)
  end

  def handle_info({ref, {:error, _reason}}, state) do
    event_id = Map.get(state.refs, ref)
    handle_task_failure(event_id, state)
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) do
    handle_task_success(ref, state)
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    event_id = Map.get(state.refs, ref)
    handle_task_failure(event_id, state)
  end

  @doc """
  Handles retrying a failed task.

  ## Parameters

    - `{:retry, event_id, event, meta, attempt}`: Retry instruction for a failed task.
      - `event_id`: The ID of the event to retry.
      - `event`: The event data.
      - `meta`: Metadata associated with the event.
      - `attempt`: The current attempt number.

  ## Callbacks

    - Restarts the task for the event with the updated attempt count.

  """
  def handle_info({:retry, event_id, event, attempt}, state) do
    Logger.info("Retrying task for event_id, attempt = #{attempt}")

    task =
      Task.Supervisor.async_nolink(Robotem.TaskSupervisor, fn ->
        process_event(event, state.process_module)
      end)

    ref = task.ref

    tasks =
      Map.put(state.tasks, event_id, %{attempt: attempt, ref: ref, event: event})

    refs = Map.put(state.refs, ref, event_id)

    {:noreply, %{state | tasks: tasks, refs: refs}}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  defp handle_task_success(ref, state) do
    event_id = Map.get(state.refs, ref)
    tasks = Map.delete(state.tasks, event_id)
    refs = Map.delete(state.refs, ref)
    {:noreply, %{state | tasks: tasks, refs: refs}}
  end

  defp handle_task_failure(event_id, state) do
    task_data = Map.get(state.tasks, event_id)
    refs = Map.delete(state.refs, task_data.ref)
    tasks = Map.delete(state.tasks, event_id)

    case task_data do
      %{attempt: attempt, event: event} when attempt < state.max_attempts ->
        # milliseconds
        delay = (:math.pow(2, attempt) * @retry_delay_base) |> trunc()
        Process.send_after(self(), {:retry, event_id, event, attempt + 1}, delay)
        {:noreply, %{state | refs: refs, tasks: tasks}}

      %{event: event} ->
        Logger.warning("Could not execute task adding to dlq")
        dlq = Map.put(state.dlq, event.seq, event)

        {:noreply, %{state | tasks: tasks, refs: refs, dlq: dlq}}
    end
  end

  defp process_event(event, module) do
    module.handle_envelope(event)
  end
end
