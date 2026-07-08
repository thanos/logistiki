defmodule Logistiki.Demo.Seeds do
  @moduledoc """
  Demo scenario seeds for Logistiki v0.1.0.

  Creates the demo business entity tree, virtual account tree, and
  entity-account relationships described in the project plan, then exposes
  helpers to process the demo business events.

  This module is idempotent within a transaction and is used by the demo
  script, the integration tests, and `priv/repo/seeds.exs`.
  """

  alias Logistiki.BusinessEntities
  alias Logistiki.Event.{
    AccountOpened,
    DepositReceived,
    FeeAssessed,
    TransferSettled
  }

  alias Logistiki.Relationships
  alias Logistiki.VirtualAccounts

  @doc "Creates the demo business entity tree and returns a map of named entities."
  @doc since: "0.1.0"
  def seed_entities do
    {:ok, acme_holdings} =
      BusinessEntities.create_entity(%{name: "Acme Holdings", entity_type: "company", status: "active"})

    {:ok, acme_trading} =
      BusinessEntities.create_entity(%{
        name: "Acme Trading Ltd",
        entity_type: "company",
        status: "active",
        parent_id: acme_holdings.id
      })

    {:ok, acme_treasury} =
      BusinessEntities.create_entity(%{
        name: "Acme Treasury Ltd",
        entity_type: "company",
        status: "active",
        parent_id: acme_holdings.id
      })

    {:ok, bluewater} =
      BusinessEntities.create_entity(%{name: "Bluewater Trust", entity_type: "trust", status: "active"})

    {:ok, bluewater_op} =
      BusinessEntities.create_entity(%{
        name: "Bluewater Operating Company",
        entity_type: "company",
        status: "active",
        parent_id: bluewater.id
      })

    %{
      acme_holdings: acme_holdings,
      acme_trading: acme_trading,
      acme_treasury: acme_treasury,
      bluewater: bluewater,
      bluewater_op: bluewater_op
    }
  end

  @doc "Creates the demo virtual account tree and returns a map of named accounts."
  @doc since: "0.1.0"
  def seed_accounts do
    tree = [
      {"ASSETS", "asset", "debit", nil, [
        {"ASSETS:CASH", "asset", "debit", nil, [
          {"ASSETS:CASH:USD", "asset", "debit", nil, [
            {"ASSETS:CASH:USD:NOSTRO", "asset", "debit", "USD", []}
          ]}
        ]}
      ]},
      {"LIABILITIES", "liability", "credit", nil, [
        {"LIABILITIES:CLIENT_DEPOSITS", "liability", "credit", nil, [
          {"LIABILITIES:CLIENT_DEPOSITS:USD", "liability", "credit", nil, [
            {"LIABILITIES:CLIENT_DEPOSITS:USD:ACME", "client", "credit", nil, [
              {"LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "client", "credit", "USD", []},
              {"LIABILITIES:CLIENT_DEPOSITS:USD:ACME:PAYROLL", "client", "credit", "USD", []},
              {"LIABILITIES:CLIENT_DEPOSITS:USD:ACME:ESCROW", "client", "credit", "USD", []}
            ]},
            {"LIABILITIES:CLIENT_DEPOSITS:USD:BLUEWATER", "client", "credit", nil, [
              {"LIABILITIES:CLIENT_DEPOSITS:USD:BLUEWATER:OPERATING", "client", "credit", "USD", []}
            ]}
          ]}
        ]}
      ]},
      {"INCOME", "income", "credit", nil, [
        {"INCOME:FEES", "income", "credit", nil, [
          {"INCOME:FEES:WIRE", "fee", "credit", "USD", []}
        ]}
      ]},
      {"EXPENSES", "expense", "debit", nil, [
        {"EXPENSES:INTEREST", "expense", "debit", "USD", []}
      ]},
      {"SUSPENSE", "suspense", "debit", nil, [
        {"SUSPENSE:USD", "suspense", "debit", "USD", []}
      ]}
    ]

    build_tree(nil, tree)
  end

  # build_tree — private helper.
  defp build_tree(parent_id, tree) do
    Enum.reduce(tree, %{}, fn {code, type, normal, currency, children}, acc ->
      attrs = %{
        code: code,
        name: code |> String.split(":") |> List.last() |> String.capitalize(),
        account_type: type,
        currency: currency,
        normal_balance: normal,
        posting_allowed: children == [],
        parent_id: parent_id
      }

      {:ok, account} = VirtualAccounts.create_account(attrs)
      child_accounts = build_tree(account.id, children)
      Map.merge(acc, Map.put(child_accounts, code, account))
    end)
  end

  @doc "Links demo entities to their accounts and returns :ok."
  @doc since: "0.1.0"
  def seed_relationships(entities, accounts) do
    Relationships.link_entity_account(
      entities.acme_holdings,
      accounts["LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING"],
      :owner
    )

    Relationships.link_entity_account(
      entities.acme_holdings,
      accounts["LIABILITIES:CLIENT_DEPOSITS:USD:ACME:PAYROLL"],
      :owner
    )

    Relationships.link_entity_account(
      entities.acme_holdings,
      accounts["LIABILITIES:CLIENT_DEPOSITS:USD:ACME:ESCROW"],
      :owner
    )

    Relationships.link_entity_account(
      entities.bluewater,
      accounts["LIABILITIES:CLIENT_DEPOSITS:USD:BLUEWATER:OPERATING"],
      :owner
    )

    :ok
  end

  @doc "Runs the full demo seed (entities, accounts, relationships). Returns `{entities, accounts}`."
  @doc since: "0.1.0"
  def run do
    entities = seed_entities()
    accounts = seed_accounts()
    seed_relationships(entities, accounts)
    {entities, accounts}
  end

  @doc "Returns the demo deposit event for `account_code`."
  @doc since: "0.1.0"
  def deposit_event(account_code, amount, entity_type \\ "corporate") do
    %DepositReceived{
      id: "demo_deposit_#{:rand.uniform(1_000_000)}",
      entity_type: entity_type,
      account_code: account_code,
      cash_account_code: "ASSETS:CASH:USD:NOSTRO",
      amount: Decimal.new(amount),
      currency: "USD",
      occurred_at: ~U[2026-07-07 12:00:00Z],
      effective_date: ~D[2026-07-07],
      source_system: "demo",
      source_id: "demo_deposit"
    }
  end

  @doc "Returns the demo transfer event from `from_code` to `to_code`."
  @doc since: "0.1.0"
  def transfer_event(from_code, to_code, amount) do
    %TransferSettled{
      id: "demo_transfer_#{:rand.uniform(1_000_000)}",
      account_code: from_code,
      destination_account_code: to_code,
      cash_account_code: "ASSETS:CASH:USD:NOSTRO",
      amount: Decimal.new(amount),
      currency: "USD",
      occurred_at: ~U[2026-07-07 13:00:00Z],
      effective_date: ~D[2026-07-07],
      source_system: "demo",
      source_id: "demo_transfer"
    }
  end

  @doc "Returns the demo fee event."
  @doc since: "0.1.0"
  def fee_event(account_code, amount) do
    %FeeAssessed{
      id: "demo_fee_#{:rand.uniform(1_000_000)}",
      entity_type: "corporate",
      account_code: account_code,
      fee_income_account_code: "INCOME:FEES:WIRE",
      amount: Decimal.new(amount),
      currency: "USD",
      fee_type: "wire_fee",
      occurred_at: ~U[2026-07-07 14:00:00Z],
      effective_date: ~D[2026-07-07],
      source_system: "demo",
      source_id: "demo_fee"
    }
  end

  @doc "Returns a no-accounting-impact account-opened event."
  @doc since: "0.1.0"
  def account_opened_event(account_code) do
    %AccountOpened{
      id: "demo_open_#{:rand.uniform(1_000_000)}",
      account_code: account_code,
      occurred_at: ~U[2026-07-07 09:00:00Z],
      effective_date: ~D[2026-07-07],
      source_system: "demo",
      source_id: "demo_open"
    }
  end
end
