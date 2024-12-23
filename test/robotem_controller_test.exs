defmodule Robotem.ControllerTest do
  use ExUnit.Case, async: true

  alias Robotem.Controller
  alias Robotem.Registry, as: ProcessRegistry
  alias Robotem.EventManager

  # Start the controller in the setup
  setup do
    # {:ok, registry} = Registry.start_link(keys: :unique, name: Robotem.ProcessRegistry)
    # Start the controller with the test registry
    # {:ok, controller} = Controller.start_link(registry: Robotem.ProcessRegistry)
    :ok
  end

  test "adds a runner successfully" do
    # Define a dummy runner module
    defmodule DummyRunner do
      def start_link(_args), do: {:ok, self()}
    end

    # Add a runner
    assert {:ok, pid} = Robotem.Controller.add(:robotem_process, Robotem.Runner.Standard)

    # Verify registration in the registry
    assert Registry.lookup(Robotem.ProcessRegistry, :robotem_process) == 1
  end
end
