# examples/deposit.exs
#
# A minimal runnable example: seed the demo chart of accounts and process a
# single deposit, then print the resulting balance.
#
# Run on a fresh, migrated database:
#
#   mix ecto.drop && mix ecto.create && mix ecto.migrate
#   mix run examples/deposit.exs

alias Logistiki.Demo.Seeds
alias Logistiki.Event.DepositReceived

Seeds.run()

event = %DepositReceived{
  id: "example_deposit_1",
  entity_type: "corporate",
  account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
  cash_account_code: "ASSETS:CASH:USD:NOSTRO",
  amount: Decimal.new("1000.00"),
  currency: "USD",
  occurred_at: ~U[2026-07-07 12:00:00Z],
  effective_date: ~D[2026-07-07],
  source_system: "example",
  source_id: "ex_1"
}

{:ok, result} = Logistiki.process(event)

IO.puts("policy:   #{inspect(result.policy)}")
IO.puts("journal:  #{inspect(result.journal.id)} (#{result.journal.status})")
IO.puts("postings: #{length(result.postings)}")

{:ok, [cash]} = Logistiki.balance("ASSETS:CASH:USD:NOSTRO")
{:ok, [client]} = Logistiki.balance("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")

IO.puts("cash net:    #{Decimal.to_string(cash.net)}")
IO.puts("client net:  #{Decimal.to_string(client.net)}")
