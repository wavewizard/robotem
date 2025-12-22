defmodule Robotem.TestUtils do
  @moduledoc """
  Utilities for testing Robotem components
  """

  alias Robotem.Runner.Simple

  @doc """
  Creates a test event with the given sequence number
  """
  def create_event(seq, event_type \\ :test_event, data \\ %{}) do
    %{
      seq: seq,
      event_type: event_type,
      data: data,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates metadata for an event
  """
  def create_metadata(overrides \\ %{}) do
    Map.merge(
      %{
        timestamp: DateTime.utc_now(),
        correlation_id: UUID.uuid4(),
        source: "test"
      },
      overrides
    )
  end

  @doc """
  Waits for a condition to be true, with timeout
  """
  def wait_for(condition, timeout_ms \\ 1000, interval_ms \\ 10) do
    start_time = System.monotonic_time(:millisecond)

    wait_loop = fn wait_loop ->
      if condition.() do
        true
      else
        elapsed = System.monotonic_time(:millisecond) - start_time

        if elapsed >= timeout_ms do
          false
        else
          Process.sleep(interval_ms)
          wait_loop.(wait_loop)
        end
      end
    end

    wait_loop.(wait_loop)
  end

  @doc """
  Asserts that the runner eventually reaches a state
  """
  def assert_runner_state(pid, expected_state_partial) do
    assert wait_for(fn ->
             try do
               state = GenServer.call(pid, :get_state)
               Map.take(state, Map.keys(expected_state_partial)) == expected_state_partial
             catch
               :exit, _ -> false
             end
           end),
           "Runner did not reach expected state: #{inspect(expected_state_partial)}"
  end

  @doc """
  Clears all Mnesia tables for tests
  """
  def clear_mnesia_tables do
    if :mnesia.system_info(:is_running) == :yes do
      tables = :mnesia.system_info(:tables)

      for table <- tables, table != :schema do
        :mnesia.clear_table(table)
      end
    end
  end

  @doc """
  Sets up test environment with mocks
  """
  def setup_test_env do
    Application.put_env(:robotem, :test_mode, true)

    # Start required applications
    Application.ensure_all_started(:mnesia)

    # Create schema if needed
    if :mnesia.system_info(:is_running) == :no do
      :mnesia.stop()
      :mnesia.create_schema([node()])
      :mnesia.start()
    end

    clear_mnesia_tables()

    :ok
  end
end
