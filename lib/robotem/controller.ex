defmodule Robotem.Controller do
  @moduledoc """
  GenServer Process to manage adding, removing and handling exits of runners
  """
  use GenServer
  alias Robotem.ProcessRegistry, as: ProcessRegistry
  alias Robotem.EventRegistry, as: Ereg

  @restart_timer 100
  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl GenServer
  def init(args) do
    Logger.info("#{__MODULE__} started")
    ProcessRegistry.clear_registry()

    state = %{
      p_registry: :robotem_process_registry,
      e_registry: :robotem_event_registry
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:register, process_module, runner_module}, state) do
    if ProcessRegistry.can_register?(process_module) do
      case DynamicSupervisor.start_child(
             Robotem.PoolSupervisor,
             Supervisor.child_spec(
               {runner_module, [process_module: process_module, last_event_seq: 0]},
               restart: :temporary
             )
           ) do
        {:ok, runner_pid} ->
          Process.monitor(runner_pid)
          do_register(runner_pid, process_module, runner_module)
          {:noreply, state}

        {:error, _reason} ->
          Process.send_after(
            self(),
            {:retry_start, process_module, runner_module, 3},
            @restart_timer
          )

          {:noreply, state}
      end
    else
      Logger.alert("Process module is already registred")
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
  def handle_info({:retry_start, process_module, runner_module, attempt}, state) do
    if attempt != 0 and ProcessRegistry.can_register?(process_module) do
      Logger.warning("attemp to restart #{process_module}, #{runner_module} :attempt: #{attempt}")

      case DynamicSupervisor.start_child(
             Robotem.PoolSupervisor,
             Supervisor.child_spec(
               {runner_module, [process_module: process_module, last_event_seq: 0]},
               restart: :temporary
             )
           ) do
        {:ok, runner_pid} ->
          Process.monitor(runner_pid)
          do_register(runner_pid, process_module, runner_module)

          {:noreply, state}

        {:error, reason} ->
          Logger.debug(" From Dynamic Supervisor #{inspect(reason)}")

          Process.send_after(
            self(),
            {:retry_start, process_module, runner_module, attempt - 1},
            @restart_timer
          )

          {:noreply, state}
      end
    else
      Logger.alert("Could not start the process")
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, :normal}, state) do
    Logger.debug("conductor terminating normally")
    Process.demonitor(ref)
    # Do the clean up
    clean_registries(pid)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    Process.demonitor(ref)
    {process, runner} = ProcessRegistry.get_process_module(pid)
    Logger.debug("#{process} is terminated because of #{inspect(reason)}")
    clean_registries(pid)
    Process.send_after(self(), {:retry_start, process, runner, 5}, @restart_timer)
    {:noreply, state}
  end

  defp clean_registries(runner_pid) do
    {process, runner} = ProcessRegistry.get_process_module(runner_pid)
    ProcessRegistry.remove(process)
    Ereg.remove(runner_pid)
  end

  defp do_register(runner_pid, process_module, runner_module) do
    ProcessRegistry.register(runner_pid, process_module, runner_module)
    Ereg.add(process_module.interested(), runner_pid)
  end

  defp clean_and_stop(runner_pid) do
    clean_registries(runner_pid)
    :ok = GenServer.stop(runner_pid)
  end

  ###### CLIENT API ##################

  def register_process(process_module, runner_module) do
    GenServer.cast(__MODULE__, {:register, process_module, runner_module})
  end
end
