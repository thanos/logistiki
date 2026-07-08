defmodule Logistiki.Events do
  @moduledoc """
  The context for business events.

  Persists, normalizes, and retrieves business events. Normalization dispatches
  to the event struct's `Logistiki.Event` implementation.

  ## Normalization

  `normalize/1` calls the event struct's `Logistiki.Event.normalize/1` callback
  and returns a `%Logistiki.Event.Normalized{}` — the flattened representation
  the knowledge layer consumes.

  ## Persistence

  `persist/1` normalizes the event and inserts a `BusinessEvent` row with both
  the raw `payload` (string-keyed map of the original struct) and the
  `normalized_payload` (the flattened form). Status starts at `"normalized"`.
  """

  import Ecto.Query

  alias Logistiki.Event
  alias Logistiki.Events.BusinessEvent
  alias Logistiki.Repo

  @doc """
  Persists a raw business event struct along with its normalized form.

  ## Arguments

    * `struct` — a business event struct implementing `Logistiki.Event`
      (e.g. `%Logistiki.Event.DepositReceived{}`).

  ## Returns

    * `{:ok, %BusinessEvent{}}` — the persisted record (status `"normalized"`).
    * `{:error, term()}` — normalization or persistence failed.

  ## Examples

      iex> {:ok, persisted} = Logistiki.Events.persist(%Logistiki.Event.DepositReceived{
      ...>   id: "evt_001", amount: Decimal.new("1000.00"), currency: "USD", ...
      ...> })
      iex> persisted.event_type
      "deposit_received"
      iex> persisted.status
      "normalized"
      iex> persisted.normalized_payload["account_code"]
      "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING"
  """
  @doc since: "0.1.0"
  @spec persist(struct()) :: {:ok, BusinessEvent.t()} | {:error, term()}
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

  @doc """
  Normalizes a business event struct through its `Logistiki.Event`
  implementation.

  ## Arguments

    * `struct` — a business event struct implementing `Logistiki.Event`.

  ## Returns

    * `{:ok, %Logistiki.Event.Normalized{}}` — the flattened event.
    * `{:error, term()}` — normalization failed.

  ## Examples

      iex> {:ok, normalized} = Logistiki.Events.normalize(%Logistiki.Event.DepositReceived{id: "evt_1"})
      iex> normalized.type
      "deposit_received"
  """
  @doc since: "0.1.0"
  @spec normalize(struct()) :: {:ok, Event.Normalized.t()} | {:error, term()}
  def normalize(%event_module{} = struct) do
    event_module.normalize(struct)
  end

  @doc """
  Fetches a persisted business event by id, raising if not found.

  ## Arguments

    * `id` — `integer()` — the `business_events` primary key.

  ## Returns

    * `%BusinessEvent{}` — the persisted event. Raises `Ecto.NoResultsError` if not found.

  ## Examples

      iex> event = Logistiki.Events.get_event!(1)
      iex> event.event_type
      "deposit_received"
  """
  @doc since: "0.1.0"
  @spec get_event!(integer()) :: BusinessEvent.t()
  def get_event!(id), do: Repo.get!(BusinessEvent, id)

  @doc """
  Lists persisted business events, optionally filtered.

  ## Arguments

    * `opts` — `keyword()` of options:
        * `:event_type` — `String.t` — e.g. `"deposit_received"`
        * `:status` — `String.t` — e.g. `"processed"`, `"blocked"`

  ## Returns

    * `[BusinessEvent.t()]` — ordered by `inserted_at` descending. Empty list
      if none match.

  ## Examples

      iex> Logistiki.Events.list_events(status: "processed")
      [%BusinessEvent{event_type: "deposit_received", ...}]

      iex> Logistiki.Events.list_events(event_type: "fee_assessed")
      [%BusinessEvent{event_type: "fee_assessed", ...}]
  """
  @doc since: "0.1.0"
  @spec list_events(keyword()) :: [BusinessEvent.t()]
  def list_events(opts \\ []) do
    BusinessEvent
    |> maybe_filter(:event_type, opts)
    |> maybe_filter(:status, opts)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Updates the status of a persisted business event.

  ## Arguments

    * `event` — `%BusinessEvent{}` — the persisted event to update.
    * `status` — `atom()` — one of `BusinessEvent.statuses/0` (e.g.
      `:processed`, `:blocked`, `:no_accounting_impact`).
    * `explanation` — `map() | nil` — optional explanation (e.g.
      `%{reason: :blocked_by_rule}`).

  ## Returns

    * `{:ok, %BusinessEvent{}}` — the updated event.
    * `{:error, %Ecto.Changeset{}}` — validation failed.

  ## Examples

      iex> {:ok, updated} = Logistiki.Events.update_status(event, :processed)
      iex> updated.status
      "processed"

      iex> {:ok, updated} = Logistiki.Events.update_status(event, :blocked, %{reason: :sanctions})
      iex> updated.explanation
      %{reason: :sanctions}
  """
  @doc since: "0.1.0"
  @spec update_status(BusinessEvent.t(), atom(), map() | nil) ::
          {:ok, BusinessEvent.t()} | {:error, Ecto.Changeset.t()}
  def update_status(%BusinessEvent{} = event, status, explanation \\ nil) do
    event
    |> BusinessEvent.changeset(%{status: Atom.to_string(status), explanation: explanation})
    |> Repo.update()
  end

  # Applies an optional equality filter from `opts` to `query`.
  defp maybe_filter(query, key, opts) do
    case Keyword.get(opts, key) do
      nil -> query
      value -> where(query, [e], field(e, ^key) == ^value)
    end
  end

  # Encodes the raw event struct into a string-keyed map for the `payload`
  # JSONB column, converting Decimal/DateTime/Date to strings.
  defp encode_payload(struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{}, fn {k, v} -> {k, encode_value(v)} end)
  end

  # Encodes a single value for JSON-safe storage.
  defp encode_value(%Decimal{} = d), do: Decimal.to_string(d)
  defp encode_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp encode_value(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_value(v) when is_map(v), do: encode_payload_map(v)
  defp encode_value(v), do: v

  # Recursively encodes a map's values.
  defp encode_payload_map(map) do
    Enum.into(map, %{}, fn {k, v} -> {k, encode_value(v)} end)
  end
end
