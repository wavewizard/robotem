defmodule Robotem.EventRegistryTest do
  alias Robotem.EventRegistry
  alias TestScore
  use ExUnit.Case

  test "start the ets table" do
    assert :test_table = EventRegistry.start(:test_table)
  end

  test "adding runner" do
    EventRegistry.start(:test_table)
    assert :ok == EventRegistry.add(:test_event, 123)
    :timer.sleep(50)
    assert [test_event: 123] == :ets.match_object(:robotem_event_registry, {:test_event, 123})
  end

  test "removing runner should remove all the instances" do
    EventRegistry.start(:test_table)
    EventRegistry.add(:test_event, 1234)
    EventRegistry.add(:test_event2, 1234)

    assert true = EventRegistry.remove(1234)

    assert [] == :ets.match(:test_table, {:"$1", 1234})
  end

  test "get_events" do
    EventRegistry.start(:test_table)
    EventRegistry.add(:test_event, 1234)
    EventRegistry.add(:test_event2, 1234)
    assert [:test_event, :test_event2] == EventRegistry.get_events(1234)
  end

  test "add multi" do
    EventRegistry.start(:test_table)
    EventRegistry.add_multi(:test_table, Robotem.Test.TestProcess.interested(), 1234)

    events =
      Robotem.Test.TestProcess.interested() |> Enum.map(fn x -> {x, 1234} end) |> Enum.reverse()

    assert events == :ets.tab2list(:test_table)
  end

  test "get_runners" do
    EventRegistry.start(:test_table)
    EventRegistry.add(:test_event, 1234)
    EventRegistry.add(:test_event, 12345)
    assert [1234, 12345] == EventRegistry.get_runners(:test_event)
  end

  test "get registered events" do
    EventRegistry.add(TestEvent, 1234)
    assert [1234] == EventRegistry.get_registered_events()
  end
end
