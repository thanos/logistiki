defmodule Logistiki.Projections.GeneralLedger do
  @moduledoc """
  A general ledger view: all postings ordered by effective date and journal.

  Each entry mirrors a `Logistiki.Projections.StatementLine` but spans all
  accounts.
  """

  @type t :: %__MODULE__{lines: [Logistiki.Projections.StatementLine.t()]}

  defstruct lines: []
end
