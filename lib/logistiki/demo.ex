defmodule Logistiki.Demo do
  @moduledoc """
  The end-to-end demo scenario for Logistiki v0.1.0 (project plan §35).

  `run_demo/0` loads the knowledge program, creates the demo entity and account
  trees, links entities to accounts, processes the demo business events, and
  prints the selected policies, generated journals, postings, balances,
  statements, and audit evidence.

  The demo is runnable from a normal Elixir OTP application without Phoenix:

      Logistiki.Demo.run_demo()

  It uses the simulation backend by default. Switch backends with
  `Logistiki.put_ledger_backend/1` before running.
  """

  alias Logistiki.Demo.Seeds

  @doc """
  Runs the full demo scenario and returns a summary map.

  Seeds the demo entity and account trees, links entities to accounts,
  processes demo business events, and prints the selected policies, generated
  journals, postings, balances, statements, and audit evidence.

  ## Arguments

    * `opts` — `keyword()` — passed through to `Logistiki.process/2`.

  ## Returns

    * `map()` — with `:entities`, `:accounts`, `:deposit_result`,
      `:fee_result`, and `:reversal` keys.

  ## Examples

      iex> Logistiki.Demo.run_demo()
      === Logistiki v0.1.0 demo ===
      ...
      === demo complete ===
      %{entities: ..., accounts: ..., deposit_result: ...}
  """
  @doc since: "0.1.0"
  def run_demo(opts \\ []) do
    IO.puts("=== Logistiki v0.1.0 demo ===")
    IO.puts("Ledger backend: #{inspect(Logistiki.ledger_backend())}")

    IO.puts("1. Load knowledge program...")
    program = Logistiki.Knowledge.load_program()
    IO.puts("   program: #{inspect(program)}")

    IO.puts("2-4. Create entity tree, account tree, and link entities to accounts...")
    {entities, accounts} = Seeds.run()
    IO.puts("   #{map_size(entities)} entities, #{map_size(accounts)} accounts")

    operating = "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING"

    IO.puts("5. Process deposit event for Acme Operating...")
    deposit = Seeds.deposit_event(operating, "1000.00")
    {:ok, deposit_result} = Logistiki.process(deposit, opts)
    print_result("deposit", deposit_result)

    IO.puts("6-8. Selected policy and generated journal/postings:")
    IO.puts("   policy: #{inspect(deposit_result.policy)}")

    IO.puts(
      "   journal: #{inspect(deposit_result.journal && deposit_result.journal.id)} (#{deposit_result.journal && deposit_result.journal.status})"
    )

    IO.puts("   postings: #{length(deposit_result.postings)}")

    IO.puts("9-10. Show balance...")
    {:ok, [cash_balance]} = Logistiki.balance("ASSETS:CASH:USD:NOSTRO")
    IO.puts("   ASSETS:CASH:USD:NOSTRO net = #{Decimal.to_string(cash_balance.net)}")

    IO.puts("11. Show statement...")
    {:ok, lines} = Logistiki.statement(operating)

    Enum.each(lines, fn line ->
      IO.puts(
        "   #{Date.to_string(line.date)} #{line.account_code} " <>
          "dr=#{fmt(line.debit)} cr=#{fmt(line.credit)} running=#{fmt(line.running_balance)}"
      )
    end)

    IO.puts("12. Process wire fee event for Acme Operating...")
    fee = Seeds.fee_event(operating, "25.00")
    {:ok, fee_result} = Logistiki.process(fee, opts)
    print_result("fee", fee_result)

    IO.puts("13. Reverse the mistaken fee...")

    {:ok, reversal} =
      Logistiki.Ledger.reverse_journal(fee_result.journal, %{reason: "mistaken fee"})

    IO.puts("   reversal journal #{reversal.journal_id} posted")

    IO.puts("14. Show balance restored...")
    {:ok, [client_balance]} = Logistiki.balance(operating)
    IO.puts("   #{operating} net = #{Decimal.to_string(client_balance.net)} (restored to -1000.00)")
    {:ok, [fee_balance]} = Logistiki.balance("INCOME:FEES:WIRE")
    IO.puts("   INCOME:FEES:WIRE net = #{Decimal.to_string(fee_balance.net)} (restored to 0)")

    IO.puts("15. Show audit evidence explaining everything...")
    trail = Logistiki.Audit.trail_for_event(deposit.id)
    IO.puts("   #{length(trail)} audit events for the deposit event:")
    Enum.each(trail, fn e -> IO.puts("     - #{e.action}") end)

    IO.puts("=== demo complete ===")

    %{
      entities: entities,
      accounts: accounts,
      deposit_result: deposit_result,
      fee_result: fee_result,
      reversal: reversal
    }
  end

  # print_result — private helper.
  defp print_result(label, %{policy: policy, journal: journal}) do
    IO.puts(
      "   #{label}: policy=#{inspect(policy)} journal=#{inspect(journal && journal.id)} status=#{inspect(journal && journal.status)}"
    )
  end

  # fmt — private helper.
  defp fmt(nil), do: "-"
  defp fmt(%Decimal{} = d), do: Decimal.to_string(d)
end
