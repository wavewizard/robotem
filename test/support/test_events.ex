defmodule Robotem.Test.Event do
  defmodule InvoiceAdded do
    defstruct [:date, :amount, :issued_to_id]
  end

  defmodule Failed do
    defstruct [:afield]
  end
end
