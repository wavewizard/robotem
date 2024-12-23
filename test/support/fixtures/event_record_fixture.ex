defmodule EventRecordFixture do
  def json_event(event_type, event_data) do
    %{
      seq: 1,
      event_type: event_type,
      event_data: event_data,
      time_stamp: DateTime.utc_now() |> DateTime.to_string(),
      aggregate_id: "111AAA222",
      event_data_format: :json,
      event_version: 1,
      meta_data_format: :json,
      meta_data: %{
        correlation_id: "1234",
        causation_id: "12345",
        client_id: "123123",
        aggregate_id: "12341"
      }
    }
    |> :json.encode()
    |> :erlang.iolist_to_binary()
  end
end
