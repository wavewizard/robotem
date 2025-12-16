defmodule Robotem.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Memento.Table.create!(Robotem.ProcessRegistry)
    # Memento.Table.create!(Robotem.ProcessConfiguration)
    Robotem.BootLoader.process_config()
    :ets.new(:robotem_event_registry, [:bag, :public, :named_table])

    children = [
      # {Robotem.Controller, []},
      {Task.Supervisor, name: Robotem.TaskSupervisor},
      {DynamicSupervisor, name: Robotem.PoolSupervisor, strategy: :one_for_one},
      # This should be configurable
      {Robotem.Exchanger, [mapper: Robotem.JsonMapper]}
      # Starts a worker by calling: Robotem.Worker.start_link(arg)
      # {Robotem.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Robotem.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
