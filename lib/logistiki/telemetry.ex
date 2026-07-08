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

  @doc "Returns the list of telemetry events Logistiki emits."
  def events, do: @events

  @doc "Emits a telemetry event with measurements and metadata."
  def emit(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  end

  @doc "Emits a `:start` event and returns the current monotonic time."
  def start(event, metadata) do
    emit(event ++ [:start], %{system_time: System.monotonic_time()}, metadata)
    System.monotonic_time()
  end

  @doc "Emits a `:stop` event with the duration since `start_mono`."
  def stop(event, start_mono, metadata) do
    duration = System.monotonic_time() - start_mono
    emit(event ++ [:stop], %{duration: duration, system_time: System.monotonic_time()}, metadata)
    duration
  end
end
