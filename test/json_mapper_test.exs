defmodule JsonMapperTest do
  use ExUnit.Case

  test "incoming event should be transoformed according to mapper" do
    payload = EventRecordFixture.json_event("Robotem.TestEvent", %{name: "Test", some_val: 1})

    assert {:ok, %Robotem.TestEvent{name: "Test", someval: 1}, _meta} =
             Robotem.JsonMapper.map(payload)
  end

  test "Unknown event should give error" do
    payload = EventRecordFixture.json_event("TestEventX", %{name: "Test", some_val: 1})
    assert {:error, _reason} = Robotem.JsonMapper.map(payload)
  end
end
