defmodule Logistiki.Accounting.Money do
  @moduledoc """
  A small money helper around `Decimal` amounts and a currency string.

  Money is represented throughout Logistiki as a `%Decimal{}` amount paired
  with a currency string. This module provides convenience constructors and
  guards. Amounts are always positive in postings; the debit/credit direction
  encodes sign.

  ## Fields

    * `amount` — `Decimal.t()` — the monetary amount
    * `currency` — `String.t()` — the currency code (e.g. `"USD"`)

  ## Example

      iex> m = Logistiki.Accounting.Money.new("1000.00", "USD")
      %Logistiki.Accounting.Money{amount: Decimal.new("1000.00"), currency: "USD"}
  """

  @typedoc """
  The struct type. See the module documentation for field details and examples.
  """
  @type t :: %__MODULE__{amount: Decimal.t(), currency: String.t()}
  defstruct [:amount, :currency]

  @doc """
  Builds a money value, coercing numeric inputs to `Decimal`.

  ## Arguments

    * `amount` — `Decimal.t() | integer() | String.t` — the amount (e.g.
      `Decimal.new("1000.00")`, `1000`, or `"1000.00"`).
    * `currency` — `String.t()` or `atom()` — the currency code (e.g. `"USD"`
      or `:USD`).

  ## Returns

    * `%__MODULE__{}` — the money value.

  ## Examples

      iex> Logistiki.Accounting.Money.new(Decimal.new("100"), "USD")
      %Logistiki.Accounting.Money{amount: Decimal.new("100"), currency: "USD"}

      iex> Logistiki.Accounting.Money.new("50.00", "EUR")
      %Logistiki.Accounting.Money{amount: Decimal.new("50.00"), currency: "EUR"}

      iex> Logistiki.Accounting.Money.new(42, :USD)
      %Logistiki.Accounting.Money{amount: Decimal.new(42), currency: "USD"}
  """
  @doc since: "0.1.0"
  @spec new(Decimal.t() | integer() | String.t(), String.t() | atom()) :: t()
  def new(amount, currency) when is_binary(currency) do
    %__MODULE__{amount: to_decimal(amount), currency: currency}
  end

  def new(amount, currency) when is_integer(amount) and is_atom(currency) do
    %__MODULE__{amount: Decimal.new(amount), currency: Atom.to_string(currency)}
  end

  @doc """
  Returns the zero amount for `currency`.

  ## Arguments

    * `currency` — `String.t()` — e.g. `"USD"`.

  ## Returns

    * `%__MODULE__{amount: Decimal.new(0), currency: currency}`.

  ## Examples

      iex> Logistiki.Accounting.Money.zero("USD")
      %Logistiki.Accounting.Money{amount: Decimal.new(0), currency: "USD"}
  """
  @doc since: "0.1.0"
  @spec zero(String.t()) :: t()
  def zero(currency), do: %__MODULE__{amount: Decimal.new(0), currency: currency}

  @doc """
  Adds two money values of the same currency.

  ## Arguments

    * `a` — `%__MODULE__{}`.
    * `b` — `%__MODULE__{}` — must have the same `currency` as `a`.

  ## Returns

    * `%__MODULE__{}` — `a.amount + b.amount` in the shared currency.

  ## Examples

      iex> a = Logistiki.Accounting.Money.new("100", "USD")
      iex> b = Logistiki.Accounting.Money.new("50", "USD")
      iex> Logistiki.Accounting.Money.add(a, b)
      %Logistiki.Accounting.Money{amount: Decimal.new("150"), currency: "USD"}
  """
  @doc since: "0.1.0"
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{amount: a, currency: c}, %__MODULE__{amount: b, currency: c}) do
    %__MODULE__{amount: Decimal.add(a, b), currency: c}
  end

  @doc """
  Subtracts `b` from `a` (same currency).

  ## Arguments

    * `a` — `%__MODULE__{}`.
    * `b` — `%__MODULE__{}` — must have the same `currency`.

  ## Returns

    * `%__MODULE__{}` — `a.amount - b.amount`.

  ## Examples

      iex> a = Logistiki.Accounting.Money.new("100", "USD")
      iex> b = Logistiki.Accounting.Money.new("30", "USD")
      iex> Logistiki.Accounting.Money.sub(a, b)
      %Logistiki.Accounting.Money{amount: Decimal.new("70"), currency: "USD"}
  """
  @doc since: "0.1.0"
  @spec sub(t(), t()) :: t()
  def sub(%__MODULE__{amount: a, currency: c}, %__MODULE__{amount: b, currency: c}) do
    %__MODULE__{amount: Decimal.sub(a, b), currency: c}
  end

  @doc """
  Negates the amount.

  ## Arguments

    * `m` — `%__MODULE__{}`.

  ## Returns

    * `%__MODULE__{}` — with `amount` negated.

  ## Examples

      iex> m = Logistiki.Accounting.Money.new("100", "USD")
      iex> Logistiki.Accounting.Money.negate(m)
      %Logistiki.Accounting.Money{amount: Decimal.new("-100"), currency: "USD"}
  """
  @doc since: "0.1.0"
  @spec negate(t()) :: t()
  def negate(%__MODULE__{amount: a, currency: c}) do
    %__MODULE__{amount: Decimal.negate(a), currency: c}
  end

  @doc """
  True when the amount is greater than zero.

  ## Arguments

    * `m` — `%__MODULE__{}`.

  ## Returns

    * `boolean()`.

  ## Examples

      iex> Logistiki.Accounting.Money.positive?(Logistiki.Accounting.Money.new("100", "USD"))
      true
      iex> Logistiki.Accounting.Money.positive?(Logistiki.Accounting.Money.zero("USD"))
      false
  """
  @doc since: "0.1.0"
  @spec positive?(t()) :: boolean()
  def positive?(%__MODULE__{amount: a}), do: Decimal.positive?(a)

  @doc """
  True when the amount equals zero.

  ## Arguments

    * `m` — `%__MODULE__{}`.

  ## Returns

    * `boolean()`.

  ## Examples

      iex> Logistiki.Accounting.Money.zero?(Logistiki.Accounting.Money.zero("USD"))
      true
  """
  @doc since: "0.1.0"
  @spec zero?(t()) :: boolean()
  def zero?(%__MODULE__{amount: a}), do: Decimal.equal?(a, Decimal.new(0))

  @doc """
  Converts the amount to integer cents (rounded down).

  ## Arguments

    * `m` — `%__MODULE__{}`.

  ## Returns

    * `integer()` — the amount × 100, rounded down.

  ## Examples

      iex> Logistiki.Accounting.Money.to_cents(Logistiki.Accounting.Money.new("1000.00", "USD"))
      100000
      iex> Logistiki.Accounting.Money.to_cents(Logistiki.Accounting.Money.new("10.99", "USD"))
      1099
  """
  @doc since: "0.1.0"
  @spec to_cents(t()) :: integer()
  def to_cents(%__MODULE__{amount: a}) do
    a |> Decimal.mult(100) |> Decimal.round(0, :down) |> Decimal.to_integer()
  end

  # Coerces a value to Decimal.
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(s) when is_binary(s), do: Decimal.new(s)
end
