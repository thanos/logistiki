defmodule Logistiki.Accounting.MoneyTest do
  use ExUnit.Case, async: true

  alias Logistiki.Accounting.Money

  describe "new/2" do
    test "builds from Decimal and string currency" do
      m = Money.new(Decimal.new("100.00"), "USD")
      assert m.amount == Decimal.new("100.00")
      assert m.currency == "USD"
    end

    test "builds from integer amount and string currency" do
      m = Money.new(42, "EUR")
      assert m.amount == Decimal.new(42)
      assert m.currency == "EUR"
    end

    test "builds from string amount and string currency" do
      m = Money.new("50.25", "GBP")
      assert m.amount == Decimal.new("50.25")
      assert m.currency == "GBP"
    end

    test "builds from integer amount and atom currency" do
      m = Money.new(100, :USD)
      assert m.amount == Decimal.new(100)
      assert m.currency == "USD"
    end
  end

  describe "zero/1" do
    test "returns zero amount for a currency" do
      m = Money.zero("USD")
      assert m.amount == Decimal.new(0)
      assert m.currency == "USD"
    end
  end

  describe "add/2" do
    test "adds two money values of the same currency" do
      a = Money.new("100", "USD")
      b = Money.new("50", "USD")
      result = Money.add(a, b)
      assert result.amount == Decimal.new("150")
      assert result.currency == "USD"
    end
  end

  describe "sub/2" do
    test "subtracts two money values of the same currency" do
      a = Money.new("100", "USD")
      b = Money.new("30", "USD")
      result = Money.sub(a, b)
      assert result.amount == Decimal.new("70")
      assert result.currency == "USD"
    end
  end

  describe "negate/1" do
    test "negates the amount" do
      m = Money.new("100", "USD")
      result = Money.negate(m)
      assert result.amount == Decimal.new("-100")
      assert result.currency == "USD"
    end
  end

  describe "positive?/1" do
    test "true when amount is greater than zero" do
      assert Money.positive?(Money.new("100", "USD"))
    end

    test "false when amount is zero" do
      refute Money.positive?(Money.zero("USD"))
    end

    test "false when amount is negative" do
      refute Money.positive?(Money.new("-50", "USD"))
    end
  end

  describe "zero?/1" do
    test "true when amount equals zero" do
      assert Money.zero?(Money.zero("USD"))
    end

    test "false when amount is positive" do
      refute Money.zero?(Money.new("100", "USD"))
    end
  end

  describe "to_cents/1" do
    test "converts a whole-dollar amount to cents" do
      assert Money.to_cents(Money.new("1000.00", "USD")) == 100_000
    end

    test "converts a fractional amount, rounded down" do
      assert Money.to_cents(Money.new("10.999", "USD")) == 1099
    end

    test "converts zero" do
      assert Money.to_cents(Money.zero("USD")) == 0
    end
  end
end
