defmodule Logistiki.Accounting.Fingerprint do
  @moduledoc """
  Canonical payload fingerprints for idempotency conflict detection.

  Two events with the same identity key but different posting-affecting fields
  must not silently share a posting outcome.
  """

  alias Logistiki.Event.Normalized

  @fingerprint_keys [
    :type,
    :amount,
    :currency,
    :account_code,
    :cash_account_code,
    :contra_account_code,
    :fee_account_code,
    :effective_date,
    :entity_type,
    :has_accounting_impact
  ]

  @doc """
  Computes a stable hex SHA-256 fingerprint of posting-affecting normalized fields.
  """
  @doc since: "0.1.1"
  @spec compute(Normalized.t() | map()) :: String.t()
  def compute(%Normalized{} = normalized) do
    normalized
    |> Normalized.to_map()
    |> compute()
  end

  def compute(map) when is_map(map) do
    canonical =
      @fingerprint_keys
      |> Enum.map(fn key ->
        atom_key = key
        string_key = Atom.to_string(key)
        value = Map.get(map, atom_key, Map.get(map, string_key))
        {string_key, canonicalize(value)}
      end)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.sort_by(&elem(&1, 0))
      |> :erlang.term_to_binary()

    :crypto.hash(:sha256, canonical) |> Base.encode16(case: :lower)
  end

  defp canonicalize(%Decimal{} = d), do: Decimal.to_string(d)
  defp canonicalize(%Date{} = d), do: Date.to_iso8601(d)
  defp canonicalize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp canonicalize(v) when is_atom(v), do: Atom.to_string(v)
  defp canonicalize(v), do: v
end
