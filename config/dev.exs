import Config

config :robotem,
  subscription: TestGenerator,
  processes: %{
    Robotem.Test.TestProcess => %{runner: :single},
    Robotem.Test.TestProcess2 => %{runner: :single}
  }
