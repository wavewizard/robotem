defmodule Robotem.Controller do
  @moduledoc """
  GenServer Process to manage adding, removing and handling exits of runners
  """
  use GenServer
  alias Robotem.ProcessRegistry, as: ProcessRegistry
  alias Robotem.EventRegistry, as: Ereg

  @restart_timer 100
  @restart_attempt 3
  require Logger

  defstruct [:remaining_attempts]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl GenServer
  def init(_args) do
    state = %__MODULE__{
      remaining_attempts: %{}
    }

    {:ok, state, {:continue, :start_processes}}
  end

  @impl GenServer
  def handle_continue(:start_processes, state) do
    Logger.info("#{__MODULE__} started")
    ProcessRegistry.clear_registry()
    processes = Robotem.ProcessConfiguration.all()

    Enum.each(processes, fn configuration ->
      GenServer.cast(self(), {:register, configuration.process_module})
    end)

    {:noreply, state}
  end

  @doc """
  Runs the process and registers it to registry 
  """

  @impl GenServer
  def handle_cast({:register, process_module}, state) do
    with {:valid, true} <- {:valid, valid_process(process_module)},
         {:can_register, true} <- {:can_register, ProcessRegistry.can_register?(process_module)},
         {:config, %Robotem.ProcessConfiguration{} = config} <-
           {:config, Robotem.ProcessConfiguration.get(process_module)} do
      Logger.info("Starting Process #{inspect(config.process_module)}")
      state = put_in(state.remaining_attempts[process_module], @restart_attempt)

      case try_start_process(config, config.runner_module) do
        :ok -> {:noreply, state}
        :error -> schedule_retry(config, state)
      end
    else
      {:valid, false} ->
        Logger.warning(
          "Ignoring to start  #{inspect(process_module)} is not valid process module"
        )

        {:noreply, state}

      {:can_register, false} ->
        Logger.warning("#{inspect(process_module)} is Already Running")
        {:noreply, state}

      {:config, nil} ->
        Logger.alert("Cannot start process #{inspect(process_module)}. No configuration found")
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:remove, robotem_process}, _from, state) do
    runner_pid = ProcessRegistry.get_pid(robotem_process)
    Logger.debug("Trying to remove #{robotem_process} with pid #{inspect(runner_pid)}")

    if runner_pid do
      clean_and_stop(runner_pid)
      Logger.debug("#{robotem_process} process runner removed")
      {:reply, :ok, state}
    else
      Logger.debug("Warning: PID not found for process #{inspect(robotem_process)}")
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_info({:retry_start, config, attempt}, state) do
    if attempt > 0 and ProcessRegistry.can_register?(config.process_module) do
      Logger.warning(
        "Attempting to restart #{config.process_module}, #{config.runner_module} :attempt: #{attempt}"
      )

      case try_start_process(config, config.runner_module) do
        :ok ->
          Logger.info("Process Started")

          _state =
            put_in(state.remaining_attempts[config.process_module], @restart_attempt)

          {:noreply, state}

        :error ->
          if attempt > 1 do
            Process.send_after(self(), {:retry_start, config, attempt - 1}, @restart_timer)
          else
            Logger.alert(
              "Could not start process #{inspect(config.process_module)} after #{@restart_attempt} attempts"
            )

            _state =
              update_in(state.remaining_attempts, &Map.delete(&1, config.process_module))
          end

          {:noreply, state}
      end
    else
      Logger.alert(
        "Could not start process #{inspect(config.process_module)} after #{@restart_attempt} attempts"
      )

      state = update_in(state.remaining_attempts, &Map.delete(&1, config.process_module))
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    DynamicSupervisor.terminate_child(Robotem.PoolSupervisor, pid)
    Process.demonitor(ref)
    {process, _runner} = ProcessRegistry.get_process_module(pid)
    Logger.debug("#{process} is terminated because of #{inspect(reason)}")
    clean_registries(pid)

    case get_in(state.remaining_attempts, [process]) do
      nil ->
        Logger.alert("Process #{inspect(process)} not found in remaining_attempts")
        {:noreply, state}

      attempt when attempt > 1 ->
        new_attempt = attempt - 1
        state = put_in(state.remaining_attempts[process], new_attempt)
        config = Robotem.ProcessConfiguration.get(process)

        if config do
          Process.send_after(self(), {:retry_start, config, new_attempt}, @restart_timer)
        end

        {:noreply, state}

      1 ->
        Logger.alert(
          "Could not start process #{inspect(process)} after #{@restart_attempt} attempts"
        )

        state = update_in(state.remaining_attempts, &Map.delete(&1, process))
        {:noreply, state}

      _ ->
        Logger.alert("Invalid attempt count for process #{inspect(process)}")
        {:noreply, state}
    end
  end

  defp clean_registries(runner_pid) do
    {process, _runner} = ProcessRegistry.get_process_module(runner_pid)
    ProcessRegistry.unregister(process)
    Ereg.remove(runner_pid)
  end

  defp do_register(runner_pid, process_module, runner_module) do
    # This one should usee process attributes to register
    ProcessRegistry.register(runner_pid, process_module, runner_module)
    Ereg.add(process_module.interested(), runner_pid)
  end

  defp clean_and_stop(runner_pid) do
    clean_registries(runner_pid)
    :ok = GenServer.stop(runner_pid)
  end

  defp valid_process(process_module) do
    Code.ensure_loaded(process_module)
    Kernel.function_exported?(process_module, :interested, 0)
  end

  defp schedule_retry(config, state) do
    attempt = get_in(state.remaining_attempts, [config.process_module]) - 1

    if attempt > 0 do
      Process.send_after(self(), {:retry_start, config, attempt}, @restart_timer)
    else
      Logger.alert(
        "Could not start process #{inspect(config.process_module)} after #{@restart_attempt} attempts"
      )

      _state = update_in(state.remaining_attempts, &Map.delete(&1, config.process_module))
    end

    {:noreply, state}
  end

  defp try_start_process(config, :single) do
    case DynamicSupervisor.start_child(
           Robotem.PoolSupervisor,
           Supervisor.child_spec({Robotem.Runner.Single, config}, restart: :temporary)
         ) do
      {:ok, runner_pid} ->
        Process.monitor(runner_pid)
        do_register(runner_pid, config.process_module, config.runner_module)
        :ok

      {:error, reason} ->
        Logger.warning("Could not start process. #{inspect(reason)}")
        :error
    end
  end

  # defp try_start_process(process_config, :concurrent) do
  # end

  # defp try_start_process(_process_config, :custom) do
  # end

  ###### CLIENT API ##################

  def register_process(process_module) do
    GenServer.cast(__MODULE__, {:register, process_module})
  end
end
