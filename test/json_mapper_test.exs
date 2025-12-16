defmodule JsonMapperTest do
  use ExUnit.Case

  test "incoming event should be transoformed according to mapper" do
    payload =
      EventRecordFixture.json_event("Robotem.Test.Event.InvoiceAdded", %{
        date: "Test",
        amount: 1,
        issued_to_id: 12
      })

    assert {:ok, %Robotem.Test.Event.InvoiceAdded{date: "Test", amount: 1, issued_to_id: 123},
            _meta} =
             Robotem.JsonMapper.map(payload)
  end

  test "Unknown event should give error" do
    payload = EventRecordFixture.json_event("TestEventX", %{name: "Test", some_val: 1})
    assert {:error, _reason} = Robotem.JsonMapper.map(payload)
  end
end
