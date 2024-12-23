defmodule Robotem do
  alias Robotem.ProcessRegistry
  alias Robotem.EventRegistry

  @moduledoc """
  Documentation for `Robotem`.
  """

  @doc """
  Starts and register runner with provided process, return pid of runner process
  """

  @spec register_process(process :: module(), runner :: module()) ::
          {:ok, pid()} | {:error, term()}
  def register_process(process, runner) do
    GenServer.call(Robotem.Controller, {:add, process, runner})
  end

  def delete_process(process_name) do
    :ok = GenServer.call(Robotem.Controller, {:remove, process_name})
  end

  def registered?(process_name) do
    ProcessRegistry.registered?(process_name)
  end
end
