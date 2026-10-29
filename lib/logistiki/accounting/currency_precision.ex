defmodule Logistiki.Accounting.CurrencyPrecision do
  @moduledoc """
  Explicit currency scale rules for posting amounts.

  Unknown currencies default to a maximum of 4 fractional digits (matching the
  posting column scale). Known ISO currencies use their conventional scale.
  """

  @scales %{
    "USD" => 2,
    "EUR" => 2,
    "GBP" => 2,
    "CHF" => 2,
    "CAD" => 2,
    "AUD" => 2,
    "JPY" => 0,
    "KRW" => 0
  }

  @default_max_scale 4

  @doc "Returns the maximum allowed fractional digits for `currency`."
  @doc since: "0.1.1"
  @spec max_scale(String.t()) :: non_neg_integer()
  def max_scale(currency) when is_binary(currency) do
    Map.get(@scales, String.upcase(currency), @default_max_scale)
  end

  @doc """
  Returns `:ok` when `amount` respects the currency scale, otherwise an error atom.
  """
  @doc since: "0.1.1"
  @spec validate_amount(Decimal.t(), String.t()) :: :ok | {:error, :precision_invalid}
  def validate_amount(%Decimal{} = amount, currency) when is_binary(currency) do
    max = max_scale(currency)
    # Decimal.scale/1 is the exponent length of the coefficient representation.
    # Compare against the number of significant fractional digits after trimming.
    fractional = fractional_digits(amount)

    if fractional <= max do
      :ok
    else
      {:error, :precision_invalid}
    end
  end

  defp fractional_digits(%Decimal{} = amount) do
    amount
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
    |> String.split(".", parts: 2)
    |> case do
      [_whole] -> 0
      [_whole, frac] -> String.length(String.trim_trailing(frac, "0"))
    end
  end
end
