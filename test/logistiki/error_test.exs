defmodule Logistiki.ErrorTest do
  use ExUnit.Case, async: true

  alias Logistiki.Error

  describe "new/2" do
    test "builds an error with all fields" do
      error =
        Error.new(:unbalanced_journal,
          message: "debits do not balance",
          details: %{currency: "USD"},
          stage: :invariant_validation
        )

      assert error.code == :unbalanced_journal
      assert error.message == "debits do not balance"
      assert error.details == %{currency: "USD"}
      assert error.stage == :invariant_validation
    end

    test "defaults message to code as string" do
      error = Error.new(:blocked_event)
      assert error.message == "blocked_event"
    end

    test "defaults details to empty map" do
      error = Error.new(:some_error)
      assert error.details == %{}
    end

    test "defaults stage to nil" do
      error = Error.new(:some_error)
      assert error.stage == nil
    end
  end

  describe "struct" do
    test "has the correct fields" do
      assert %Error{code: :test, message: "msg", details: %{}, stage: nil} ==
               %Error{code: :test, message: "msg"}
    end
  end
end
