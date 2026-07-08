defmodule Logistiki.Events.BuiltInEventsTest do
  use ExUnit.Case, async: true

  alias Logistiki.Event

  alias Logistiki.Event.{
    AccountOpened,
    DepositReceived,
    FeeAssessed,
    InterestAccrued,
    InvoicePaid,
    RefundIssued,
    TransferSettled
  }

  describe "TransferSettled" do
    test "event_type returns transfer_settled" do
      assert Event.event_type(%TransferSettled{}) == "transfer_settled"
    end

    test "normalize flattens event-specific fields" do
      event = %TransferSettled{
        id: "evt_t1",
        account_code: "LIAB:ACME:OPERATING",
        destination_account_code: "LIAB:ACME:PAYROLL",
        cash_account_code: "ASSETS:CASH",
        amount: Decimal.new("500.00"),
        currency: "USD"
      }

      {:ok, normalized} = Event.normalize(event)
      assert normalized.type == "transfer_settled"
      assert normalized.destination_account_code == "LIAB:ACME:PAYROLL"
      assert normalized.cash_account_code == "ASSETS:CASH"
      assert normalized.has_accounting_impact
    end
  end

  describe "InterestAccrued" do
    test "event_type returns interest_accrued" do
      assert Event.event_type(%InterestAccrued{}) == "interest_accrued"
    end

    test "normalize flattens interest_expense_account_code" do
      event = %InterestAccrued{
        id: "evt_i1",
        account_code: "LIAB:ACME:OPERATING",
        interest_expense_account_code: "EXPENSES:INTEREST",
        amount: Decimal.new("5.00"),
        currency: "USD"
      }

      {:ok, normalized} = Event.normalize(event)
      assert normalized.type == "interest_accrued"
      assert normalized.interest_expense_account_code == "EXPENSES:INTEREST"
    end
  end

  describe "RefundIssued" do
    test "event_type returns refund_issued" do
      assert Event.event_type(%RefundIssued{}) == "refund_issued"
    end

    test "normalize flattens cash_account_code" do
      event = %RefundIssued{
        id: "evt_r1",
        account_code: "LIAB:ACME:OPERATING",
        cash_account_code: "ASSETS:CASH:USD:NOSTRO",
        amount: Decimal.new("100.00"),
        currency: "USD"
      }

      {:ok, normalized} = Event.normalize(event)
      assert normalized.type == "refund_issued"
      assert normalized.cash_account_code == "ASSETS:CASH:USD:NOSTRO"
    end
  end

  describe "InvoicePaid" do
    test "event_type returns invoice_paid" do
      assert Event.event_type(%InvoicePaid{}) == "invoice_paid"
    end

    test "normalize flattens counterparty_account_code" do
      event = %InvoicePaid{
        id: "evt_iv1",
        account_code: "LIAB:ACME:OPERATING",
        counterparty_account_code: "LIAB:VENDOR",
        cash_account_code: "ASSETS:CASH",
        amount: Decimal.new("250.00"),
        currency: "USD"
      }

      {:ok, normalized} = Event.normalize(event)
      assert normalized.type == "invoice_paid"
      assert normalized.counterparty_account_code == "LIAB:VENDOR"
    end
  end

  describe "AccountOpened" do
    test "event_type returns account_opened" do
      assert Event.event_type(%AccountOpened{}) == "account_opened"
    end

    test "has no accounting impact by default" do
      {:ok, normalized} = Event.normalize(%AccountOpened{id: "evt_ao1"})
      refute normalized.has_accounting_impact
    end
  end

  describe "DepositReceived" do
    test "normalize flattens cash_account_code" do
      event = %DepositReceived{
        id: "evt_d1",
        account_code: "LIAB:ACME",
        cash_account_code: "ASSETS:CASH",
        amount: Decimal.new("1000.00"),
        currency: "USD"
      }

      {:ok, normalized} = Event.normalize(event)
      assert normalized.cash_account_code == "ASSETS:CASH"
    end
  end

  describe "FeeAssessed" do
    test "normalize flattens fee_type and fee_income_account_code" do
      event = %FeeAssessed{
        id: "evt_f1",
        account_code: "LIAB:ACME",
        fee_income_account_code: "INCOME:FEES:WIRE",
        amount: Decimal.new("25.00"),
        currency: "USD",
        fee_type: "wire_fee"
      }

      {:ok, normalized} = Event.normalize(event)
      assert normalized.fee_type == "wire_fee"
      assert normalized.fee_income_account_code == "INCOME:FEES:WIRE"
    end
  end

  describe "Event dispatchers" do
    test "Event.event_type/1 dispatches to the struct module" do
      assert Event.event_type(%DepositReceived{}) == "deposit_received"
      assert Event.event_type(%FeeAssessed{}) == "fee_assessed"
      assert Event.event_type(%TransferSettled{}) == "transfer_settled"
      assert Event.event_type(%InterestAccrued{}) == "interest_accrued"
      assert Event.event_type(%RefundIssued{}) == "refund_issued"
      assert Event.event_type(%InvoicePaid{}) == "invoice_paid"
      assert Event.event_type(%AccountOpened{}) == "account_opened"
    end

    test "Event.normalize/1 dispatches to the struct module" do
      {:ok, n} = Event.normalize(%DepositReceived{id: "x"})
      assert n.type == "deposit_received"
    end
  end
end
