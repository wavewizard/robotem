defmodule Robotem.Event do
  defstruct [:event_type, :event_data, :seq, :meta_data]

  @type t() :: %__MODULE__{
          event_type: atom(),
          event_data: map(),
          seq: integer(),
          meta_data: map()
        }
end
