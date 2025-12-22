ExUnit.start()

# Override the module in test config
defmodule Robotem.ProcessConfiguration do
  # This will override the real module in test environment
  def update_last_seen(_module, _seq), do: :ok
  def get(_module), do: nil
  def all, do: []
  def save(_config), do: :ok
  def clear_registry, do: :ok
end

# Ensure TaskSupervisor is available
Task.Supervisor.start_link(name: Robotem.TaskSupervisor)
