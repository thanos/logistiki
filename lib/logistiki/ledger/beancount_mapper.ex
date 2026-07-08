defmodule Logistiki.Ledger.BeancountMapper do
  @moduledoc """
  Maps Logistiki virtual accounts, journals, and postings to Beancount
  directives and back.

  Beancount is the accounting oracle, not the domain model. Beancount-specific
  structs never escape this module (and the `Logistiki.Ledger.Beancount`
  backend). The public API only sees `Logistiki.Projections.*` structs.

  ## Account code mapping

  Logistiki virtual account codes are colon-separated and human-readable
  (`LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING`). The mapper produces
  deterministic Beancount account names by mapping the account type to a
  Beancount root (`Assets`, `Liabilities`, `Equity`, `Income`, `Expenses`) and
  CamelCasing the remaining segments.
  """

  alias Logistiki.Accounting.{Journal, Posting}
  alias Logistiki.VirtualAccounts.VirtualAccount

  @root_by_type %{
    "asset" => "Assets",
    "settlement" => "Assets",
    "liability" => "Liabilities",
    "client" => "Liabilities",
    "suspense" => "Liabilities",
    "clearing" => "Liabilities",
    "tax" => "Liabilities",
    "equity" => "Equity",
    "income" => "Income",
    "fee" => "Income",
    "expense" => "Expenses"
  }

  @normal_debit_types ~w(asset expense settlement)a

  @doc "Maps a `%VirtualAccount{}` to a deterministic Beancount account name."
  @doc since: "0.1.0"
  def to_beancount_account(%VirtualAccount{code: code, account_type: type}) do
    root = Map.fetch!(@root_by_type, type)
    segments = String.split(code, ":")
    # Drop the Logistiki root segment and CamelCase the rest.
    rest = Enum.drop(segments, 1) |> Enum.map(&camelize/1)
    Enum.join([root | rest], ":")
  end

  @doc "Maps a list of accounts to Beancount `open` directives."
  @doc since: "0.1.0"
  def to_beancount_opens(accounts, date \\ ~D[2026-01-01]) do
    Enum.map(accounts, fn account ->
      Beancount.open(date, to_beancount_account(account), [account.currency || "USD"])
    end)
  end

  @doc "Maps a Logistiki posting to a Beancount posting (signed amount)."
  @doc since: "0.1.0"
  def to_beancount_posting(%Posting{} = posting, %VirtualAccount{} = account) do
    beancount_account = to_beancount_account(account)
    signed = signed_amount(posting, account)
    Beancount.posting(beancount_account, signed, posting.currency)
  end

  @doc "Maps a Logistiki journal + postings + accounts to a Beancount transaction directive."
  @doc since: "0.1.0"
  def to_beancount_directive(%Journal{} = journal, postings, accounts_by_code) do
    date = journal.effective_date || Date.utc_today()
    flag = "*"
    payee = nil
    narration = journal.description || "Logistiki journal"

    bc_postings =
      Enum.map(postings, fn p ->
        account = Map.fetch!(accounts_by_code, p.account_code)
        to_beancount_posting(p, account)
      end)

    Beancount.transaction(date, flag, payee, narration, bc_postings,
      metadata:
        %{
          "logistiki_event_id" => journal.event_id,
          "logistiki_policy" => journal.selected_policy,
          "logistiki_template" => journal.selected_template,
          "logistiki_journal_id" => journal.id
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Enum.into(%{})
    )
  end

  @doc "Converts a Beancount balances result into a map of account -> balance."
  @doc since: "0.1.0"
  def from_beancount_balance(%Beancount.Query.Result{rows: rows, columns: columns}) do
    account_idx = Enum.find_index(columns, &(&1 == "account"))
    balance_idx = Enum.find_index(columns, &(&1 == "balance"))

    Enum.into(rows, %{}, fn row ->
      account = Enum.at(row, account_idx)
      balance = Enum.at(row, balance_idx)
      {account, balance}
    end)
  end

  def from_beancount_balance({:error, _} = err), do: err

  @doc "Converts a Beancount query row into a plain map of column -> value."
  @doc since: "0.1.0"
  def from_beancount_entry(%Beancount.Query.Result{rows: rows, columns: columns}) do
    Enum.map(rows, fn row ->
      Enum.zip(columns, row) |> Enum.into(%{})
    end)
  end

  @doc "Returns the beancount root for a Logistiki account type."
  @doc since: "0.1.0"
  def root_for_type(type), do: Map.fetch!(@root_by_type, to_string(type))

  @doc "True when the account type has a debit normal balance."
  @doc since: "0.1.0"
  def normal_debit?(type) when type in @normal_debit_types, do: true
  def normal_debit?(_), do: false

  @doc """
  Returns the signed Beancount amount for a Logistiki posting.

  Beancount encodes direction as sign: debits are positive, credits are
  negative, regardless of account type. Account balances then read naturally
  (assets positive, liabilities/income negative) and match Logistiki's
  net = debit - credit projection.
  """
  @doc since: "0.1.0"
  def signed_amount(%Posting{debit_credit: "debit", amount: a}, _account), do: a
  def signed_amount(%Posting{debit_credit: "credit", amount: a}, _account), do: Decimal.negate(a)

  # camelize — private helper.
  defp camelize(segment) do
    segment
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(&capitalize_first/1)
  end

  # capitalize_first — private helper.
  defp capitalize_first(""), do: ""

  # capitalize_first — private helper.
  defp capitalize_first(str) do
    {first, rest} = String.next_grapheme(str)
    String.upcase(first) <> rest
  end
end
