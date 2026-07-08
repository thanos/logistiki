defmodule Logistiki.Projections.Balance do
  @moduledoc """
  A derived balance for an account (or aggregation of accounts).

  Balances are never authoritative stored state. They are projections over
  immutable postings. `net` is signed: positive for a debit balance, negative
  for a credit balance.
  """

  @typedoc """
  The struct type. See the module documentation for field details and examples.
  """
  @type t :: %__MODULE__{
          account_id: term() | nil,
          account_code: String.t() | nil,
          currency: String.t(),
          debit_total: Decimal.t(),
          credit_total: Decimal.t(),
          net: Decimal.t(),
          posting_count: non_neg_integer()
        }

  defstruct [:account_id, :account_code, :currency, debit_total: Decimal.new(0), credit_total: Decimal.new(0), net: Decimal.new(0), posting_count: 0]

  @doc "Builds a balance from a row of `{debit_total, credit_total, count}` for `currency`."
  @doc since: "0.1.0"
  def build(account_code, currency, debit_total, credit_total, count) do
    %__MODULE__{
      account_code: account_code,
      currency: currency,
      debit_total: debit_total || Decimal.new(0),
      credit_total: credit_total || Decimal.new(0),
      net: Decimal.sub(debit_total || Decimal.new(0), credit_total || Decimal.new(0)),
      posting_count: count || 0
    }
  end

  @doc "True when the balance is non-zero."
  @doc since: "0.1.0"
  def nonzero?(%__MODULE__{net: net}), do: not Decimal.equal?(net, Decimal.new(0))
end
