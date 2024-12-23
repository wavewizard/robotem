defmodule Robotem.Test.TestProcess do
  def interested, do: [Robotem.Test.Event.InvoiceAdded, Robotem.Test.Event.Failed]

  def handle_envelop(event, meta_data) do
    event = struct(event.event_type, event.event_data)
    act_on(event, meta_data)
  end

  def act_on(%Robotem.Test.Event.InvoiceAdded{} = e, _meta_data) do
    IO.puts("Test Invoice Added #{inspect(e)}")
    {:ok, :action}
  end

  def act_on(%Robotem.Test.Event.Failed{} = _e, _meta_data) do
    raise "Process Failed"
  end
end
