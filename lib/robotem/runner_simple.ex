defmodule Robotem.Runner.Simple do
  @moduledoc """
  Single-process runner with proper sequence gap handling.
  """
  use GenServer
  require Logger

  alias Robotem.ProcessConfiguration

  @type runner_status :: :syncing | :processing | :idle

  @retry_delay_base 200
  defstruct [
    :last_seen,
    :process_module,
    :tasks,
    :buffer,
    :dlq,
    :refs,
    :max_attempts,
    :runner_status,
    :sync_ref,
    :task_supervisor
  ]

  @doc """
  Starts the runner.

  Args should include:
  - process_module: the module that handles events
  - last_seen: optional, last processed sequence (default 0)
  - task_supervisor: optional, name of Task.Supervisor (default Robotem.TaskSupervisor)
  """
  def start_link(args) when is_map(args) do
    # Extract name option if provided
    name = Map.get(args, :name, args.process_module)

    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl GenServer
  def init(args) do
    task_supervisor = Map.get(args, :task_supervisor, Robotem.TaskSupervisor)

    state = %__MODULE__{
      process_module: args.process_module,
      tasks: %{},
      dlq: %{},
      refs: %{},
      max_attempts: args[:max_attempts] || 3,
      buffer: [],
      last_seen: args[:last_seen] || 0,
      runner_status: :idle,
      sync_ref: nil,
      task_supervisor: task_supervisor
    }

    {:ok, state}
  end

  @doc """
  Handles new events with metadata.
  """
  @impl GenServer
  def handle_cast({:new_event, event, meta_data}, state) do
    Logger.debug(
      "Runner #{state.process_module} received event #{event.seq}, last_seen: #{state.last_seen}, status: #{state.runner_status}"
    )

    cond do
      # Already processed or currently processing
      Map.has_key?(state.tasks, event.seq) or event.seq <= state.last_seen ->
        Logger.debug("Ignoring event #{event.seq} - already processed or processing")
        {:noreply, state}

      # In-order event
      event.seq == state.last_seen + 1 and state.runner_status != :syncing ->
        new_state = process_in_order_event(event, meta_data, state)
        {:noreply, new_state}

      # Out-of-order but we're already syncing
      state.runner_status == :syncing ->
        Logger.debug("Buffering event #{event.seq} while syncing")
        buffer = [%{seq: event.seq, event: event, meta: meta_data} | state.buffer]
        # Keep sorted descending
        buffer = Enum.sort_by(buffer, & &1.seq, :desc)
        {:noreply, %{state | buffer: buffer}}

      # Gap detected, need to sync
      event.seq > state.last_seen + 1 ->
        Logger.warning(
          "Sequence gap detected for #{state.process_module}. Expected #{state.last_seen + 1}, got #{event.seq}"
        )

        new_state = start_sync(state.last_seen + 1, event.seq - 1, state)
        {:noreply, new_state}

      # Should never reach here
      true ->
        Logger.error("Unexpected condition for event #{event.seq}")
        {:noreply, state}
    end
  end

  def handle_cast(:crash, _state) do
    raise "Intentional crash"
  end

  @impl GenServer
  def handle_info({ref, result}, state) do
    case result do
      :ok ->
        handle_task_success(ref, state)

      {:ok, _} ->
        handle_task_success(ref, state)

      {:error, reason} ->
        Logger.error("Task failed: #{inspect(reason)}")
        event_id = Map.get(state.refs, ref)
        handle_task_failure(event_id, state)

      other ->
        Logger.warning("Unexpected task result: #{inspect(other)}")
        handle_task_success(ref, state)
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) do
    handle_task_success(ref, state)
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    Logger.error("Task crashed: #{inspect(reason)}")
    event_id = Map.get(state.refs, ref)
    handle_task_failure(event_id, state)
  end

  @doc """
  Handles retrying a failed task.
  """
  def handle_info({:retry, event_id, event, attempt}, state) do
    Logger.info("Retrying event #{event_id}, attempt #{attempt}")

    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        process_event(event, state.process_module)
      end)

    ref = task.ref

    tasks =
      Map.put(state.tasks, event_id, %{attempt: attempt, ref: ref, event: event})

    refs = Map.put(state.refs, ref, event_id)

    {:noreply, %{state | tasks: tasks, refs: refs}}
  end

  @doc """
  Handles sync completion.
  """
  def handle_info({:sync_complete, from_seq, to_seq, events}, state) do
    Logger.info("Sync complete for #{state.process_module}, processed #{length(events)} events")

    # Process synced events in order
    {new_state, _} =
      Enum.reduce(events, {state, state.last_seen}, fn event, {acc_state, expected_seq} ->
        if event.seq == expected_seq + 1 do
          new_state = process_in_order_event(event.event, event.meta, acc_state)
          {new_state, event.seq}
        else
          # Still missing events - should not happen
          Logger.error("Sync returned out-of-order events")
          {acc_state, expected_seq}
        end
      end)

    # Process buffered events that are now in-order
    {final_state, processed_count} = process_buffer(new_state)

    Logger.info("Processed #{processed_count} buffered events after sync")

    # Check if we can return to idle
    runner_status = if map_size(final_state.tasks) == 0, do: :idle, else: :processing

    {:noreply, %{final_state | runner_status: runner_status, sync_ref: nil}}
  end

  @doc """
  Handles sync failure.
  """
  def handle_info({:sync_failed, reason}, state) do
    Logger.error("Sync failed for #{state.process_module}: #{inspect(reason)}")
    # TODO: Implement retry logic for sync
    {:noreply, %{state | runner_status: :idle, sync_ref: nil}}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # Private functions

  defp process_in_order_event(event, meta_data, state) do
    # Update last_seen in configuration (async)
    Task.start(fn ->
      ProcessConfiguration.update_last_seen(state.process_module, event.seq)
    end)

    # Start processing task
    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        process_event(event, state.process_module)
      end)

    ref = task.ref

    tasks =
      Map.put(state.tasks, event.seq, %{
        attempt: 1,
        ref: ref,
        event: event,
        meta: meta_data
      })

    refs = Map.put(state.refs, ref, event.seq)

    %{
      state
      | tasks: tasks,
        refs: refs,
        last_seen: event.seq,
        runner_status: :processing
    }
  end

  defp start_sync(from_seq, to_seq, state) do
    Logger.info("Starting sync for #{state.process_module} from #{from_seq} to #{to_seq}")

    # Start sync task
    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        sync_missing_events(state.process_module, from_seq, to_seq)
      end)

    # Buffer current state and go to syncing
    %{
      state
      | runner_status: :syncing,
        sync_ref: task.ref
    }
  end

  defp sync_missing_events(process_module, from_seq, to_seq) do
    # This would call Eventos or another service to get missing events
    # For now, return empty list as placeholder
    Logger.info("Fetching missing events #{from_seq}..#{to_seq} for #{process_module}")

    # Simulate fetching events
    events =
      Enum.map(from_seq..to_seq, fn seq ->
        %{
          seq: seq,
          # Placeholder
          event: %{event_type: :unknown, seq: seq},
          meta: %{timestamp: DateTime.utc_now()}
        }
      end)

    {:ok, events}
  end

  defp process_buffer(state) do
    # Sort buffer ascending
    sorted_buffer = Enum.sort_by(state.buffer, & &1.seq)

    Enum.reduce_while(sorted_buffer, {state, 0}, fn buffered, {acc_state, count} ->
      if buffered.seq == acc_state.last_seen + 1 do
        # Can process this event
        new_state = process_in_order_event(buffered.event, buffered.meta, acc_state)
        {:cont, {%{new_state | buffer: List.delete(acc_state.buffer, buffered)}, count + 1}}
      else
        # Buffer is still out of order, stop processing
        {:halt, {acc_state, count}}
      end
    end)
  end

  defp handle_task_success(ref, state) do
    case Map.get(state.refs, ref) do
      nil ->
        Logger.warning("Received success for unknown task ref #{inspect(ref)}")
        {:noreply, state}

      event_id ->
        tasks = Map.delete(state.tasks, event_id)
        refs = Map.delete(state.refs, ref)

        # Determine new runner status
        runner_status =
          cond do
            # Still have tasks -> keep processing
            map_size(tasks) > 0 -> :processing
            # In syncing state -> stay in syncing
            state.runner_status == :syncing -> :syncing
            # Buffer has events -> stay processing (will process buffer)
            length(state.buffer) > 0 -> :processing
            # No tasks, not syncing, no buffer -> idle
            true -> :idle
          end

        {:noreply, %{state | tasks: tasks, refs: refs, runner_status: runner_status}}
    end
  end

  defp handle_task_failure(event_id, state) do
    case Map.get(state.tasks, event_id) do
      nil ->
        Logger.warning("Task failure for unknown event #{event_id}")
        {:noreply, state}

      %{attempt: attempt, event: event} when attempt < state.max_attempts ->
        refs = Map.delete(state.refs, state.tasks[event_id].ref)
        tasks = Map.delete(state.tasks, event_id)

        # Schedule retry with exponential backoff
        delay = (:math.pow(2, attempt) * @retry_delay_base) |> trunc()
        Process.send_after(self(), {:retry, event_id, event, attempt + 1}, delay)

        {:noreply, %{state | refs: refs, tasks: tasks}}

      %{event: event} ->
        Logger.warning("Max retries exceeded for event #{event_id}, adding to DLQ")
        refs = Map.delete(state.refs, state.tasks[event_id].ref)
        tasks = Map.delete(state.tasks, event_id)
        dlq = Map.put(state.dlq, event.seq, %{event: event, attempts: state.max_attempts})

        {:noreply, %{state | tasks: tasks, refs: refs, dlq: dlq}}
    end
  end

  defp process_event(event, module) do
    try do
      module.handle_envelope(event)
    rescue
      e ->
        Logger.error("Process module #{module} crashed: #{inspect(e)}")
        reraise e, __STACKTRACE__
    end
  end
end
