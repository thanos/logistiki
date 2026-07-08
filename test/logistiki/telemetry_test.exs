defmodule Logistiki.TelemetryTest do
  use ExUnit.Case, async: true

  alias Logistiki.Telemetry

  describe "events/0" do
    test "returns a list of event name lists" do
      events = Telemetry.events()
      assert is_list(events)
      assert Enum.all?(events, &is_list/1)
    end

    test "includes the process events" do
      events = Telemetry.events()
      assert [:logistiki, :event, :process, :start] in events
      assert [:logistiki, :event, :process, :stop] in events
    end

    test "includes knowledge evaluate events" do
      events = Telemetry.events()
      assert [:logistiki, :knowledge, :evaluate, :start] in events
      assert [:logistiki, :knowledge, :evaluate, :stop] in events
    end
  end

  describe "emit/3" do
    test "emits a telemetry event" do
      ref = make_ref()
      :telemetry.attach(ref, [:test, :emit], fn _, _, _, _ -> nil end, nil)

      assert :ok = Telemetry.emit([:test, :emit], %{duration: 1}, %{key: :value})

      :telemetry.detach(ref)
    end
  end

  describe "start/2" do
    test "emits a start event and returns monotonic time" do
      ref = make_ref()
      :telemetry.attach(ref, [:test, :start, :start], fn _, _, _, _ -> nil end, nil)

      time = Telemetry.start([:test, :start], %{test: true})
      assert is_integer(time)

      :telemetry.detach(ref)
    end
  end

  describe "stop/3" do
    test "emits a stop event with duration and returns it" do
      ref = make_ref()
      :telemetry.attach(ref, [:test, :stop, :stop], fn _, _, _, _ -> nil end, nil)

      start_time = System.monotonic_time()
      duration = Telemetry.stop([:test, :stop], start_time, %{test: true})
      assert is_integer(duration)
      assert duration >= 0

      :telemetry.detach(ref)
    end
  end
end
