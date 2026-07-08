defmodule Logistiki.Events do
  @moduledoc """
  The context for business events.

  Persists, normalizes, and retrieves business events. Normalization dispatches
  to the event struct's `Logistiki.Event` implementation.
  """

  import Ecto.Query

  alias Logistiki.Event
  alias Logistiki.Events.BusinessEvent
  alias Logistiki.Repo

  @doc "Persists a raw business event struct along with its normalized form."
  def persist(%event_module{} = struct) do
    with {:ok, normalized} <- event_module.normalize(struct) do
      attrs = %{
        event_type: normalized.type,
        source_system: normalized.source_system,
        source_id: normalized.source_id,
        actor_id: normalized.actor_id,
        occurred_at: normalized.occurred_at,
        effective_date: normalized.effective_date,
        payload: encode_payload(struct),
        normalized_payload: Event.Normalized.to_map(normalized),
        status: "normalized",
        metadata: Map.get(struct, :metadata, %{})
      }

      %BusinessEvent{}
      |> BusinessEvent.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc "Normalizes a business event struct through its `Logistiki.Event` implementation."
  def normalize(%event_module{} = struct) do
    event_module.normalize(struct)
  end

  @doc "Fetches a persisted business event by id."
  def get_event!(id), do: Repo.get!(BusinessEvent, id)

  @doc "Lists persisted business events, optionally filtered by `:event_type` or `:status`."
  def list_events(opts \\ []) do
    BusinessEvent
    |> maybe_filter(:event_type, opts)
    |> maybe_filter(:status, opts)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  @doc "Updates the status of a persisted business event (e.g. `:processed`, `:blocked`)."
  def update_status(%BusinessEvent{} = event, status, explanation \\ nil) do
    event
    |> BusinessEvent.changeset(%{status: Atom.to_string(status), explanation: explanation})
    |> Repo.update()
  end

  defp maybe_filter(query, key, opts) do
    case Keyword.get(opts, key) do
      nil -> query
      value -> where(query, [e], field(e, ^key) == ^value)
    end
  end

  defp encode_payload(struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{}, fn {k, v} -> {k, encode_value(v)} end)
  end

  defp encode_value(%Decimal{} = d), do: Decimal.to_string(d)
  defp encode_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp encode_value(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_value(v) when is_map(v), do: encode_payload_map(v)
  defp encode_value(v), do: v

  defp encode_payload_map(map) do
    Enum.into(map, %{}, fn {k, v} -> {k, encode_value(v)} end)
  end
end
