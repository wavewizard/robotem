defmodule Robotem.JsonMapper do
  @moduledoc """
  Maps incoming Projected event record represented as json to
  erlang term. Successfully parse will result in {:ok, event, meta_data}
  """
  require Logger
  # Maps incoming event record to triple that can be used by Robotem process

  def map(payload) do
    push = fn key, value, acc -> [{:erlang.binary_to_existing_atom(key), value} | acc] end

    case :json.decode(payload, :ok, %{object_push: push}) do
      {decoded, :ok, _} ->
        case parse_event_type(decoded.event_type) do
          {:ok, event_type} ->
            event = %{event_type: event_type, event_data: decoded.event_data}
            meta_data = construct_meta_data(decoded)

            {:ok, event, meta_data}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp construct_meta_data(payload) when is_map(payload) do
    %{
      seq: payload.seq,
      timestamp: payload.time_stamp |> DateTime.from_iso8601() |> elem(1),
      event_version: payload.event_version
    }
    |> Map.merge(payload.meta_data)
  end

  defp parse_event_type(event_type) when is_binary(event_type) do
    {:ok, String.to_existing_atom(event_type)}
  rescue
    ArgumentError -> {:error, "event is not known #{event_type}"}
  end
end
