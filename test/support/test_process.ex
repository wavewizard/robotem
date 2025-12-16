defmodule Robotem.Test.TestProcess do
  def interested() do
    [Robotem.Test.Event.InvoiceAdded, Robotem.Test.Event.Failed]
  end

  @description "This is a test process"

  def description() do
    @description
  end

  ## this can be process_group
  # @process_type :process

  def handle_envelope(event) do
    event_struct = struct(event.event_type, event.event_data)
    act_on(event_struct, event.meta_data)
  end

  def act_on(%Robotem.Test.Event.InvoiceAdded{} = e, _meta_data) do
    IO.puts("Test Invoice Added #{inspect(e)}")
    {:ok, :action}
  end

  def act_on(%Robotem.Test.Event.Failed{} = _e, _meta_data) do
    raise "Process Failed"
  end
end
