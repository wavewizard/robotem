defmodule Robotem.RegistrySupervisor do
  use Supervisor
  alias Robotem.ProcessRegistry
  alias Robotem.EventRegistry

  def start_link(_) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    children = []

    Supervisor.init(children, strategy: :one_for_one)
  end
end
