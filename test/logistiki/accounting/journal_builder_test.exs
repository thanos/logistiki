defmodule Logistiki.Accounting.JournalBuilderTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.Accounting.{Journal, JournalBuilder, Posting}
  alias Logistiki.Event.Normalized
  alias Logistiki.Knowledge.Result

  describe "build/2" do
    test "returns nil journal for no-accounting-impact result" do
      result = %Result{policy: nil, blocked: false, requires_approval: false, explanation: %{}}
      event = Normalized.new(%{id: "evt_1", type: "account_opened"})

      assert {:ok, nil, [], explanation} = JournalBuilder.build(result, event)
      assert explanation[:policy] == nil
    end

    test "builds a draft journal with postings from a knowledge result" do
      result = %Result{
        policy: :cash_deposit,
        template: :cash_deposit,
        template_postings: [
          %{
            sequence: 1,
            direction: :debit,
            role: :cash_account,
            amount_var: :event_amount,
            currency_var: :event_currency
          },
          %{
            sequence: 2,
            direction: :credit,
            role: :client_liability_account,
            amount_var: :event_amount,
            currency_var: :event_currency
          }
        ],
        account_roles: %{
          cash_account: "ASSETS:CASH:USD:NOSTRO",
          client_liability_account: "LIAB:ACME"
        },
        blocked: false,
        requires_approval: false,
        explanation: %{reason: :unique, selected: :cash_deposit}
      }

      event =
        Normalized.new(%{
          id: "evt_1",
          type: "deposit_received",
          amount: Decimal.new("1000.00"),
          currency: "USD",
          account_code: "LIAB:ACME",
          effective_date: ~D[2026-07-07],
          source_system: "test"
        })

      assert {:ok, journal, postings, explanation} = JournalBuilder.build(result, event)
      assert journal.status == "draft"
      assert journal.selected_policy == "cash_deposit"
      assert journal.event_id == "evt_1"
      assert journal.idempotency_key == "evt:evt_1:policy:cash_deposit"
      assert length(postings) == 2
      assert explanation[:policy] == :cash_deposit
    end

    test "generates random idempotency key when event has no id" do
      result = %Result{
        policy: :cash_deposit,
        template: :cash_deposit,
        template_postings: [
          %{
            sequence: 1,
            direction: :debit,
            role: :cash_account,
            amount_var: :event_amount,
            currency_var: :event_currency
          },
          %{
            sequence: 2,
            direction: :credit,
            role: :client_liability_account,
            amount_var: :event_amount,
            currency_var: :event_currency
          }
        ],
        account_roles: %{cash_account: "A", client_liability_account: "B"},
        explanation: %{}
      }

      event =
        Normalized.new(%{
          id: nil,
          type: "deposit_received",
          amount: Decimal.new("1.00"),
          currency: "USD"
        })

      {:ok, journal, _, _} = JournalBuilder.build(result, event)
      assert String.starts_with?(journal.idempotency_key, "policy:cash_deposit:")
    end

    test "returns error when a role is missing" do
      result = %Result{
        policy: :cash_deposit,
        template: :cash_deposit,
        template_postings: [
          %{
            sequence: 1,
            direction: :debit,
            role: :cash_account,
            amount_var: :event_amount,
            currency_var: :event_currency
          }
        ],
        account_roles: %{},
        explanation: %{}
      }

      event =
        Normalized.new(%{
          id: "e1",
          type: "deposit_received",
          amount: Decimal.new("1.00"),
          currency: "USD"
        })

      assert {:error, %{code: :account_not_found}} = JournalBuilder.build(result, event)
    end
  end

  describe "build_reversal/3" do
    test "builds a reversal journal that negates the original postings" do
      journal = %Journal{
        id: 42,
        event_id: "evt_r1",
        source_system: "test",
        source_type: "deposit_received",
        source_id: "s1",
        selected_policy: "cash_deposit",
        selected_template: "cash_deposit",
        idempotency_key: "evt:evt_r1:policy:cash_deposit"
      }

      postings = [
        %Posting{
          account_code: "A",
          debit_credit: "debit",
          amount: Decimal.new("100"),
          currency: "USD",
          sequence: 1,
          id: 1
        },
        %Posting{
          account_code: "B",
          debit_credit: "credit",
          amount: Decimal.new("100"),
          currency: "USD",
          sequence: 2,
          id: 2
        }
      ]

      {:ok, reversal, reversal_postings} =
        JournalBuilder.build_reversal(journal, postings, reason: "test")

      assert reversal.status == "draft"
      assert reversal.reversal_of_id == 42
      assert reversal.event_id == "evt_r1"
      assert reversal.explanation[:reversal_of] == 42
      assert reversal.explanation[:reason] == "test"
      assert reversal.idempotency_key == "reversal:evt:evt_r1:policy:cash_deposit"

      assert length(reversal_postings) == 2
      assert hd(reversal_postings).debit_credit == "credit"
    end

    test "uses default description when not provided" do
      journal = %Journal{id: 5, idempotency_key: "k"}
      postings = []
      {:ok, reversal, _} = JournalBuilder.build_reversal(journal, postings, %{})
      assert reversal.description == "Reversal of journal 5"
    end

    test "uses custom description when provided" do
      journal = %Journal{id: 5, idempotency_key: "k"}
      {:ok, reversal, _} = JournalBuilder.build_reversal(journal, [], description: "custom")
      assert reversal.description == "custom"
    end

    test "uses default effective_date when not provided" do
      journal = %Journal{id: 5, idempotency_key: "k"}
      {:ok, reversal, _} = JournalBuilder.build_reversal(journal, [], %{})
      assert reversal.effective_date == Date.utc_today()
    end

    test "uses custom idempotency_key when provided" do
      journal = %Journal{id: 5, idempotency_key: "k"}
      {:ok, reversal, _} = JournalBuilder.build_reversal(journal, [], idempotency_key: "custom_key")
      assert reversal.idempotency_key == "custom_key"
    end
  end
end
