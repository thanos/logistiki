defmodule Logistiki.Ledger.Behaviour do
  @moduledoc """
  Behaviour implemented by ledger backends.

  The runtime calls the configured backend (see `config :logistiki,
  :ledger_backend`) to execute journals, reverse them, and compute
  projections.

  Initial backends:

    * `Logistiki.Ledger.Simulation` — fast, deterministic, no external deps
    * `Logistiki.Ledger.Beancount` — the accounting oracle via `beancount_ex`

  Backends must not leak their own types into the public API. Results are
  returned as `Logistiki.Projections.*` structs.
  """

  alias Logistiki.Accounting.Journal
  alias Logistiki.Projections.{Balance, StatementLine, TrialBalance}

  @callback execute_journal(journal :: Journal.t(), opts :: keyword()) ::
              {:ok, Logistiki.Ledger.Result.t()} | {:error, term()}

  @callback reverse_journal(journal :: Journal.t(), attrs :: map(), opts :: keyword()) ::
              {:ok, Logistiki.Ledger.Result.t()} | {:error, term()}

  @callback balance(account :: term(), opts :: keyword()) ::
              {:ok, Balance.t()} | {:error, term()}

  @callback statement(account :: term(), opts :: keyword()) ::
              {:ok, [StatementLine.t()]} | {:error, term()}

  @callback trial_balance(opts :: keyword()) ::
              {:ok, TrialBalance.t()} | {:error, term()}
end
