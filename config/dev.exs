import Config

config :robotem,
  subscription: TestGenerator,
  processes: %{Robotem.Test.TestProcess => %{runner: Robotem.Runner.Standard}}
