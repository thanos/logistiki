defmodule Logistiki.Accounting.Money do
  @moduledoc """
  A small money helper around `Decimal` amounts and a currency string.

  Money is represented throughout Logistiki as a `%Decimal{}` amount paired
  with a currency string. This module provides convenience constructors and
  guards. Amounts are always positive in postings; the debit/credit direction
  encodes sign.
  """

  @type t :: %__MODULE__{amount: Decimal.t(), currency: String.t()}
  defstruct [:amount, :currency]

  @doc "Builds a money value, coercing numeric inputs to `Decimal`."
  def new(amount, currency) when is_binary(currency) do
    %__MODULE__{amount: to_decimal(amount), currency: currency}
  end

  def new(amount, currency) when is_integer(amount) and is_atom(currency) do
    %__MODULE__{amount: Decimal.new(amount), currency: Atom.to_string(currency)}
  end

  @doc "Returns the zero amount for `currency`."
  def zero(currency), do: %__MODULE__{amount: Decimal.new(0), currency: currency}

  @doc "Adds two money values of the same currency."
  def add(%__MODULE__{amount: a, currency: c}, %__MODULE__{amount: b, currency: c}) do
    %__MODULE__{amount: Decimal.add(a, b), currency: c}
  end

  @doc "Subtracts `b` from `a` (same currency)."
  def sub(%__MODULE__{amount: a, currency: c}, %__MODULE__{amount: b, currency: c}) do
    %__MODULE__{amount: Decimal.sub(a, b), currency: c}
  end

  @doc "Negates the amount."
  def negate(%__MODULE__{amount: a, currency: c}) do
    %__MODULE__{amount: Decimal.negate(a), currency: c}
  end

  @doc "True when the amount is greater than zero."
  def positive?(%__MODULE__{amount: a}), do: Decimal.positive?(a)

  @doc "True when the amount equals zero."
  def zero?(%__MODULE__{amount: a}), do: Decimal.equal?(a, Decimal.new(0))

  @doc "Converts the amount to integer cents (rounded down)."
  def to_cents(%__MODULE__{amount: a}) do
    a |> Decimal.mult(100) |> Decimal.round(0, :down) |> Decimal.to_integer()
  end

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp to_decimal(s) when is_binary(s), do: Decimal.new(s)
end
