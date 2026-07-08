defmodule Logistiki.Telemetry do
  @moduledoc """
  Telemetry event helpers for the accounting pipeline.

  Events are emitted at the start and stop of each pipeline stage so external
  handlers can measure throughput and latency. Example event names:

      [:logistiki, :event, :process, :start]
      [:logistiki, :event, :process, :stop]
      [:logistiki, :knowledge, :evaluate, :stop]
      [:logistiki, :journal, :build, :stop]
      [:logistiki, :ledger, :execute, :stop]
      [:logistiki, :projection, :generate, :stop]
      [:logistiki, :audit, :write, :stop]

  ## Attaching a handler

      :telemetry.attach("my-handler", [:logistiki, :ledger, :execute, :stop],
        fn _event, measurements, metadata, _config ->
          IO.puts("Ledger executed in \#{measurements.duration} µs (backend: \#{metadata.backend})")
        end,
        nil
      )
  """

  @events [
    [:logistiki, :event, :process, :start],
    [:logistiki, :event, :process, :stop],
    [:logistiki, :event, :normalize, :stop],
    [:logistiki, :knowledge, :evaluate, :start],
    [:logistiki, :knowledge, :evaluate, :stop],
    [:logistiki, :policy, :select, :stop],
    [:logistiki, :template, :select, :stop],
    [:logistiki, :journal, :build, :stop],
    [:logistiki, :invariant, :validate, :stop],
    [:logistiki, :ledger, :execute, :start],
    [:logistiki, :ledger, :execute, :stop],
    [:logistiki, :projection, :generate, :stop],
    [:logistiki, :audit, :write, :stop]
  ]

  @doc """
  Returns the list of telemetry events Logistiki emits.

  ## Returns

    * `[[atom()]]` — a list of event name lists.

  ## Examples

      iex> [:logistiki, :event, :process, :start] in Logistiki.Telemetry.events()
      true
      iex> length(Logistiki.Telemetry.events())
      13
  """
  @doc since: "0.1.0"
  @spec events() :: [[atom(), ...]]
  def events, do: @events

  @doc """
  Emits a telemetry event with measurements and metadata.

  This is a thin wrapper around `:telemetry.execute/3`. Measurements and
  metadata must be maps (not keyword lists) per the telemetry contract.

  ## Arguments

    * `event` — `[atom()]` — the event name, e.g.
      `[:logistiki, :knowledge, :evaluate, :stop]`
    * `measurements` — `map()` — e.g. `%{duration: 1234}` or `%{system_time: ...}`
    * `metadata` — `map()` — e.g. `%{event_type: "deposit_received", policy: :cash_deposit}`

  ## Returns

    * `:ok` — always (per `:telemetry.execute/3` semantics).

  ## Examples

      iex> Logistiki.Telemetry.emit([:logistiki, :journal, :build, :stop],
      ...>   %{duration: 120},
      ...>   %{policy: :cash_deposit, posting_count: 2}
      ...> )
      :ok
  """
  @doc since: "0.1.0"
  @spec emit([atom(), ...], map(), map()) :: :ok
  def emit(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  end

  @doc """
  Emits a `:start` event and returns the current monotonic time.

  The returned monotonic time should be passed to `stop/3` to compute the
  duration. The event name is suffixed with `:start`.

  ## Arguments

    * `event` — `[atom()]` — the base event name, e.g.
      `[:logistiki, :event, :process]`
    * `metadata` — `map()` — e.g. `%{event_type: "deposit_received"}`

  ## Returns

    * `integer()` — the current monotonic time (`System.monotonic_time/0`).

  ## Examples

      iex> start = Logistiki.Telemetry.start([:logistiki, :event, :process], %{event_type: "deposit_received"})
      iex> is_integer(start)
      true
  """
  @doc since: "0.1.0"
  @spec start([atom(), ...], map()) :: integer()
  def start(event, metadata) do
    emit(event ++ [:start], %{system_time: System.monotonic_time()}, metadata)
    System.monotonic_time()
  end

  @doc """
  Emits a `:stop` event with the duration since `start_mono`.

  The event name is suffixed with `:stop`. The duration is computed as
  `System.monotonic_time() - start_mono`.

  ## Arguments

    * `event` — `[atom()]` — the base event name, e.g.
      `[:logistiki, :event, :process]`
    * `start_mono` — `integer()` — the monotonic time returned by `start/2`
    * `metadata` — `map()` — e.g. `%{policy: :cash_deposit}`

  ## Returns

    * `integer()` — the duration in native time units.

  ## Examples

      iex> start = Logistiki.Telemetry.start([:logistiki, :ledger, :execute], %{backend: Simulation})
      iex> duration = Logistiki.Telemetry.stop([:logistiki, :ledger, :execute], start, %{backend: Simulation})
      iex> is_integer(duration)
      true
  """
  @doc since: "0.1.0"
  @spec stop([atom(), ...], integer(), map()) :: integer()
  def stop(event, start_mono, metadata) do
    duration = System.monotonic_time() - start_mono
    emit(event ++ [:stop], %{duration: duration, system_time: System.monotonic_time()}, metadata)
    duration
  end
end
