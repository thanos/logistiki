defmodule Logistiki.VirtualAccounts do
  @moduledoc """
  The context for hierarchical virtual accounts.

  Virtual accounts represent accounting accounts and account-like projections.
  They form a tree maintained through a closure table
  (`Logistiki.VirtualAccounts.VirtualAccountClosure`).

  ## Rules enforced

    * account code is unique
    * only leaf accounts (no children) may allow postings
    * posting accounts require a currency
    * aggregation accounts may have a nil currency
    * a child cannot be created under a posting account
    * cycles are forbidden (the closure table is rewritten on move)
  """

  import Ecto.Query

  alias Logistiki.Repo
  alias Logistiki.VirtualAccounts.VirtualAccount
  alias Logistiki.VirtualAccounts.VirtualAccountClosure

  @doc """
  Creates a new virtual account. When `:parent_id` is given the account is
  linked as a child and the closure table is updated.

  ## Arguments

    * `attrs` — `map()` or `keyword()` of account attributes:
        * `:code` — `String.t` — **required** (e.g. `"ASSETS:CASH:USD:NOSTRO"`)
        * `:name` — `String.t` — **required** (e.g. `"Nostro USD"`)
        * `:account_type` — `String.t` — **required** (e.g. `"asset"`, `"liability"`)
        * `:status` — `String.t` — defaults to `"active"`
        * `:parent_id` — `integer() | nil` — the parent account id; `nil` for roots
        * `:currency` — `String.t` — **required when `posting_allowed: true`** (e.g. `"USD"`)
        * `:posting_allowed` — `boolean()` — defaults to `false`; only `true` for leaf accounts
        * `:normal_balance` — `String.t` — `"debit"` or `"credit"`
        * `:external_id` — `String.t`
        * `:metadata` — `map()`

  ## Returns

    * `{:ok, %VirtualAccount{}}` — the created account.
    * `{:error, %Ecto.Changeset{}}` — validation failed.
    * `{:error, :parent_not_found}` — the `parent_id` does not reference an existing account.
    * `{:error, :parent_is_posting_account}` — the parent is a posting account (cannot have children).

  ## Examples

      iex> {:ok, root} = Logistiki.VirtualAccounts.create_account(%{
      ...>   code: "ASSETS", name: "Assets", account_type: "asset"
      ...> })
      iex> root.parent_id
      nil

      iex> {:ok, leaf} = Logistiki.VirtualAccounts.create_account(%{
      ...>   code: "ASSETS:CASH:USD:NOSTRO", name: "Nostro USD", account_type: "asset",
      ...>   currency: "USD", posting_allowed: true, normal_balance: "debit",
      ...>   parent_id: root.id
      ...> })
      iex> leaf.posting_allowed
      true

      iex> {:error, changeset} = Logistiki.VirtualAccounts.create_account(%{
      ...>   code: "BAD", name: "Bad", account_type: "asset", posting_allowed: true
      ...> })
      iex> errors_on(changeset)[:currency]
      ["can't be blank when posting is allowed"]
  """
  @doc since: "0.1.0"
  @spec create_account(map()) :: {:ok, VirtualAccount.t()} | {:error, term()}
  def create_account(attrs \\ %{}) do
    attrs = Map.new(attrs)

    Repo.transaction(fn ->
      with :ok <- ensure_parent_allows_children(attrs[:parent_id]),
           {:ok, account} <-
             %VirtualAccount{}
             |> VirtualAccount.changeset(attrs)
             |> Repo.insert(),
           {:ok, _} <- insert_closure_for(account) do
        account
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # Checks that the parent exists and is not a posting account (posting
  # accounts cannot have children — only leaf accounts post).
  defp ensure_parent_allows_children(nil), do: :ok

  defp ensure_parent_allows_children(parent_id) do
    case Repo.get(VirtualAccount, parent_id) do
      nil -> {:error, :parent_not_found}
      %VirtualAccount{posting_allowed: true} -> {:error, :parent_is_posting_account}
      %VirtualAccount{} -> :ok
    end
  end

  @doc """
  Updates a virtual account's mutable attributes (not its parent — use
  `move_account/2` to change the parent).

  ## Arguments

    * `account` — `%VirtualAccount{}` — the account to update.
    * `attrs` — `map()` of attributes to change (e.g.
      `%{status: "frozen", normal_balance: "credit"}`).

  ## Returns

    * `{:ok, %VirtualAccount{}}` — the updated account.
    * `{:error, %Ecto.Changeset{}}` — validation failed.

  ## Examples

      iex> {:ok, updated} = Logistiki.VirtualAccounts.update_account(account, %{status: "frozen"})
      iex> updated.status
      "frozen"
  """
  @doc since: "0.1.0"
  @spec update_account(VirtualAccount.t(), map()) ::
          {:ok, VirtualAccount.t()} | {:error, Ecto.Changeset.t()}
  def update_account(%VirtualAccount{} = account, attrs) do
    account
    |> VirtualAccount.changeset(attrs)
    |> Ecto.Changeset.change()
    |> Repo.update()
  end

  @doc """
  Fetches a single account by id, raising if not found.

  ## Arguments

    * `id` — `integer()` — the account primary key.

  ## Returns

    * `%VirtualAccount{}` — the account. Raises `Ecto.NoResultsError` if not found.

  ## Examples

      iex> account = Logistiki.VirtualAccounts.get_account!(10)
      iex> account.code
      "ASSETS:CASH:USD:NOSTRO"
  """
  @doc since: "0.1.0"
  @spec get_account!(integer()) :: VirtualAccount.t()
  def get_account!(id), do: Repo.get!(VirtualAccount, id)

  @doc """
  Fetches a single account by code, raising if not found.

  ## Arguments

    * `code` — `String.t()` — the account code (e.g. `"ASSETS:CASH:USD:NOSTRO"`).

  ## Returns

    * `%VirtualAccount{}` — the account. Raises `Ecto.NoResultsError` if not found.

  ## Examples

      iex> account = Logistiki.VirtualAccounts.get_account_by_code!("ASSETS:CASH:USD:NOSTRO")
      iex> account.currency
      "USD"
  """
  @doc since: "0.1.0"
  @spec get_account_by_code!(String.t()) :: VirtualAccount.t()
  def get_account_by_code!(code) do
    Repo.get_by!(VirtualAccount, code: code)
  end

  @doc """
  Fetches a single account by code.

  ## Arguments

    * `code` — `String.t()` — the account code (e.g. `"ASSETS:CASH:USD:NOSTRO"`).

  ## Returns

    * `{:ok, %VirtualAccount{}}` — the account was found.
    * `{:error, :not_found}` — no account with that code.

  ## Examples

      iex> {:ok, account} = Logistiki.VirtualAccounts.get_account_by_code("ASSETS:CASH:USD:NOSTRO")
      iex> account.code
      "ASSETS:CASH:USD:NOSTRO"

      iex> {:error, :not_found} = Logistiki.VirtualAccounts.get_account_by_code("UNKNOWN")
  """
  @doc since: "0.1.0"
  @spec get_account_by_code(String.t()) :: {:ok, VirtualAccount.t()} | {:error, :not_found}
  def get_account_by_code(code) do
    case Repo.get_by(VirtualAccount, code: code) do
      nil -> {:error, :not_found}
      account -> {:ok, account}
    end
  end

  @doc """
  Fetches a single account by id.

  ## Arguments

    * `id` — `integer()` — the account primary key.

  ## Returns

    * `{:ok, %VirtualAccount{}}` — the account was found.
    * `{:error, :not_found}` — no account with that id.

  ## Examples

      iex> {:ok, account} = Logistiki.VirtualAccounts.get_account(10)
      iex> account.code
      "ASSETS:CASH:USD:NOSTRO"

      iex> {:error, :not_found} = Logistiki.VirtualAccounts.get_account(999)
  """
  @doc since: "0.1.0"
  @spec get_account(integer()) :: {:ok, VirtualAccount.t()} | {:error, :not_found}
  def get_account(id) do
    case Repo.get(VirtualAccount, id) do
      nil -> {:error, :not_found}
      account -> {:ok, account}
    end
  end

  @doc """
  Resolves an account from either a `%VirtualAccount{}`, an id, or an account
  code. Tries code first for binary inputs, then falls back to numeric id.

  ## Arguments

    * `account` — one of:
        * `%VirtualAccount{}` — returned directly
        * `String.t` — interpreted as an account code first, then as a numeric id
        * `integer()` — interpreted as an account id

  ## Returns

    * `{:ok, %VirtualAccount{}}` — the account was found.
    * `{:error, :not_found}` — the account could not be resolved.

  ## Examples

      iex> {:ok, account} = Logistiki.VirtualAccounts.resolve("ASSETS:CASH:USD:NOSTRO")
      iex> account.id
      10

      iex> {:ok, account} = Logistiki.VirtualAccounts.resolve(10)
      iex> account.code
      "ASSETS:CASH:USD:NOSTRO"

      iex> {:ok, account} = Logistiki.VirtualAccounts.resolve(existing_account_struct)
  """
  @doc since: "0.1.0"
  @spec resolve(VirtualAccount.t() | String.t() | integer()) ::
          {:ok, VirtualAccount.t()} | {:error, :not_found}
  def resolve(%VirtualAccount{} = account), do: {:ok, account}

  def resolve(code) when is_binary(code) do
    case get_account_by_code(code) do
      {:ok, account} -> {:ok, account}
      {:error, :not_found} -> resolve_by_id(code)
    end
  end

  # Falls back to numeric-id lookup when the binary is not a known code.
  defp resolve_by_id(value) do
    case Integer.parse(value) do
      {id, ""} ->
        case Repo.get(VirtualAccount, id) do
          nil -> {:error, :not_found}
          account -> {:ok, account}
        end

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists accounts, optionally filtered.

  ## Arguments

    * `opts` — `keyword()` of options:
        * `:status` — `String.t` — e.g. `"active"`, `"frozen"`
        * `:account_type` — `String.t` — e.g. `"asset"`, `"liability"`
        * `:currency` — `String.t` — e.g. `"USD"`
        * `:parent_id` — `integer() | nil` — filter by parent; `nil` lists roots

  ## Returns

    * `[VirtualAccount.t()]` — ordered by code ascending. Empty list if none match.

  ## Examples

      iex> Logistiki.VirtualAccounts.list_accounts(account_type: "asset")
      [%VirtualAccount{code: "ASSETS", ...}, %VirtualAccount{code: "ASSETS:CASH", ...}]

      iex> Logistiki.VirtualAccounts.list_accounts(status: "active", currency: "USD")
      [%VirtualAccount{code: "ASSETS:CASH:USD:NOSTRO", ...}]
  """
  @doc since: "0.1.0"
  @spec list_accounts(keyword()) :: [VirtualAccount.t()]
  def list_accounts(opts \\ []) do
    VirtualAccount
    |> maybe_filter(:status, opts)
    |> maybe_filter(:account_type, opts)
    |> maybe_filter(:currency, opts)
    |> maybe_filter(:parent_id, opts)
    |> order_by([a], asc: a.code)
    |> Repo.all()
  end

  # Applies an optional equality filter from `opts` to `query`.
  defp maybe_filter(query, key, opts) do
    case Keyword.get(opts, key) do
      nil -> query
      value -> where(query, [a], field(a, ^key) == ^value)
    end
  end

  @doc """
  Lists direct children of `account`.

  ## Arguments

    * `account` — `%VirtualAccount{}` — the parent account.

  ## Returns

    * `[VirtualAccount.t()]` — ordered by code. Empty list if no children.

  ## Examples

      iex> Logistiki.VirtualAccounts.list_children(assets_root)
      [%VirtualAccount{code: "ASSETS:CASH", ...}]
  """
  @doc since: "0.1.0"
  @spec list_children(VirtualAccount.t()) :: [VirtualAccount.t()]
  def list_children(%VirtualAccount{id: id}) do
    Repo.all(from(a in VirtualAccount, where: a.parent_id == ^id, order_by: [asc: a.code]))
  end

  @doc """
  Lists all descendants of `account` (excluding the account itself), using the
  closure table for O(rows) performance.

  ## Arguments

    * `account` — `%VirtualAccount{}` — the root of the subtree.

  ## Returns

    * `[VirtualAccount.t()]` — ordered by code. Empty list if no descendants.

  ## Examples

      iex> Logistiki.VirtualAccounts.list_descendants(cash_root)
      [%VirtualAccount{code: "ASSETS:CASH:USD", ...}, %VirtualAccount{code: "ASSETS:CASH:USD:NOSTRO", ...}]
  """
  @doc since: "0.1.0"
  @spec list_descendants(VirtualAccount.t()) :: [VirtualAccount.t()]
  def list_descendants(%VirtualAccount{id: id}) do
    descendants_query(id)
    |> order_by([a], asc: a.code)
    |> Repo.all()
  end

  @doc """
  Lists all ancestors of `account` ordered from nearest to farthest, using the
  closure table.

  ## Arguments

    * `account` — `%VirtualAccount{}` — the descendant account.

  ## Returns

    * `[VirtualAccount.t()]` — ordered by `depth` ascending. Empty list if the
      account is a root.

  ## Examples

      iex> Logistiki.VirtualAccounts.list_ancestors(nostro_account)
      [%VirtualAccount{code: "ASSETS:CASH:USD", ...}, %VirtualAccount{code: "ASSETS:CASH", ...}, %VirtualAccount{code: "ASSETS", ...}]
  """
  @doc since: "0.1.0"
  @spec list_ancestors(VirtualAccount.t()) :: [VirtualAccount.t()]
  def list_ancestors(%VirtualAccount{id: id}) do
    ancestors_query(id)
    |> order_by([a, c], asc: c.depth)
    |> Repo.all()
  end

  @doc """
  Moves `account` under `new_parent` (which may be `nil` for a root), rewriting
  the closure table for the entire subtree. Cycles are prevented.

  ## Arguments

    * `account` — `%VirtualAccount{}` — the account to move.
    * `new_parent` — one of:
        * `%VirtualAccount{}` — the new parent
        * `nil` — move to root
        * `integer()` — the new parent's id

  ## Returns

    * `{:ok, %VirtualAccount{}}` — the moved account with updated `parent_id`.
    * `{:error, :cycle_detected}` — moving would create a cycle.
    * `{:error, term()}` — the move failed (rolled back).

  ## Examples

      iex> {:ok, moved} = Logistiki.VirtualAccounts.move_account(cash_account, new_root)
      iex> moved.parent_id
      20

      iex> {:error, :cycle_detected} = Logistiki.VirtualAccounts.move_account(parent, child)
  """
  @doc since: "0.1.0"
  @spec move_account(VirtualAccount.t(), VirtualAccount.t() | integer() | nil) ::
          {:ok, VirtualAccount.t()} | {:error, :cycle_detected | term()}
  def move_account(%VirtualAccount{} = account, new_parent) do
    new_parent_id = parent_id_from(new_parent)

    if creates_cycle?(account.id, new_parent_id) do
      {:error, :cycle_detected}
    else
      Repo.transaction(fn -> perform_move(account, new_parent_id) end)
    end
  end

  # Performs the actual move inside a transaction: deletes old closure rows,
  # updates the parent_id, and re-links the subtree under the new parent.
  defp perform_move(account, new_parent_id) do
    delete_old_closure_on_move(account.id)

    with {:ok, updated} <-
           account
           |> VirtualAccount.changeset(%{parent_id: new_parent_id})
           |> Ecto.Changeset.change()
           |> Repo.update(),
         {:ok, _} <- link_subtree_under_new_parent(updated) do
      updated
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # Resolves `new_parent` to an id: nil -> nil, struct -> id, id -> id.
  defp parent_id_from(nil), do: nil
  defp parent_id_from(%VirtualAccount{id: id}), do: id
  defp parent_id_from(id) when is_binary(id), do: id

  # Checks whether moving `id` under `new_parent_id` would create a cycle.
  # A cycle occurs if `id` is already an ancestor of (or equal to) `new_parent_id`.
  defp creates_cycle?(_id, nil), do: false

  defp creates_cycle?(id, new_parent_id) do
    from(c in VirtualAccountClosure,
      where: c.ancestor_id == ^id and c.descendant_id == ^new_parent_id
    )
    |> Repo.exists?()
  end

  @doc false
  @spec insert_closure_for(VirtualAccount.t()) ::
          {:ok, :root | :child} | {:error, :parent_closure_missing}
  def insert_closure_for(%VirtualAccount{id: id, parent_id: nil}) do
    insert_self_closure(id)
    {:ok, :root}
  end

  def insert_closure_for(%VirtualAccount{id: id, parent_id: parent_id}) do
    insert_self_closure(id)
    insert_inherited_closure(id, parent_id)
    {:ok, :child}
  end

  # Inserts the self-row (depth 0) for `id`.
  defp insert_self_closure(id) do
    Repo.insert_all(
      VirtualAccountClosure,
      [%{ancestor_id: id, descendant_id: id, depth: 0, inserted_at: DateTime.utc_now(:second)}]
    )
  end

  # Inserts inherited closure rows: for every ancestor of `parent_id`, add a
  # row (ancestor, id, depth+1). Fails if the parent has no closure.
  defp insert_inherited_closure(id, parent_id) do
    rows =
      from(c in VirtualAccountClosure,
        where: c.descendant_id == ^parent_id,
        select: {c.ancestor_id, c.depth}
      )
      |> Repo.all()
      |> Enum.map(fn {ancestor_id, depth} ->
        %{
          ancestor_id: ancestor_id,
          descendant_id: id,
          depth: depth + 1,
          inserted_at: DateTime.utc_now(:second)
        }
      end)

    if rows == [] do
      {:error, :parent_closure_missing}
    else
      Repo.insert_all(VirtualAccountClosure, rows)
    end
  end

  # Deletes closure rows connecting this subtree to ancestors above the
  # subtree (rows whose descendant is in the subtree but ancestor is not).
  defp delete_old_closure_on_move(id) do
    from(c in VirtualAccountClosure,
      where:
        c.descendant_id in subquery(
          from(sc in VirtualAccountClosure, where: sc.ancestor_id == ^id, select: sc.descendant_id)
        ) and
          c.ancestor_id not in subquery(
            from(sc in VirtualAccountClosure, where: sc.ancestor_id == ^id, select: sc.ancestor_id)
          )
    )
    |> Repo.delete_all()

    :ok
  end

  # Rewrites the closure for a subtree moved under a new parent. For every
  # descendant d of id and every ancestor a of the new parent, adds
  # closure(a, d, depth(a, parent) + depth(id, d) + 1).
  defp link_subtree_under_new_parent(%VirtualAccount{id: _id, parent_id: nil}) do
    # When moving to root, the self-closure row already exists from the original
    # insert. The delete_old_closure_on_move already removed the inherited rows.
    # Nothing more to do — the self-row is preserved.
    {:ok, :root}
  end

  defp link_subtree_under_new_parent(%VirtualAccount{id: id, parent_id: parent_id}) do
    descendant_rows =
      from(d in VirtualAccountClosure,
        where: d.ancestor_id == ^id,
        select: {d.descendant_id, d.depth}
      )
      |> Repo.all()

    ancestor_rows =
      from(a in VirtualAccountClosure,
        where: a.descendant_id == ^parent_id,
        select: {a.ancestor_id, a.depth}
      )
      |> Repo.all()

    new_rows =
      for {d_id, d_depth} <- descendant_rows,
          {a_id, a_depth} <- ancestor_rows do
        %{
          ancestor_id: a_id,
          descendant_id: d_id,
          depth: a_depth + d_depth + 1,
          inserted_at: DateTime.utc_now(:second)
        }
      end

    Repo.insert_all(VirtualAccountClosure, new_rows)
    {:ok, :linked}
  end

  # Base query for descendants (depth > 0) of `id` via the closure table.
  defp descendants_query(id) do
    from(a in VirtualAccount,
      join: c in VirtualAccountClosure,
      on: c.descendant_id == a.id,
      where: c.ancestor_id == ^id and c.depth > 0
    )
  end

  # Base query for ancestors (depth > 0) of `id` via the closure table.
  defp ancestors_query(id) do
    from(a in VirtualAccount,
      join: c in VirtualAccountClosure,
      on: c.ancestor_id == a.id,
      where: c.descendant_id == ^id and c.depth > 0
    )
  end

  @doc """
  Returns the ids of all descendants of `account` (including itself).

  Uses the closure table directly — faster than `list_descendants/1` when only
  ids are needed (e.g. for balance aggregation queries).

  ## Arguments

    * `account` — `%VirtualAccount{}`.

  ## Returns

    * `[integer()]` — descendant ids including `account.id`.

  ## Examples

      iex> Logistiki.VirtualAccounts.descendant_ids(assets_root)
      [1, 2, 3, 4]
  """
  @doc since: "0.1.0"
  @spec descendant_ids(VirtualAccount.t()) :: [integer()]
  def descendant_ids(%VirtualAccount{id: id}) do
    Repo.all(from(c in VirtualAccountClosure, where: c.ancestor_id == ^id, select: c.descendant_id))
  end

  @doc """
  Returns the ids of all ancestors of `account` (including itself).

  ## Arguments

    * `account` — `%VirtualAccount{}`.

  ## Returns

    * `[integer()]` — ancestor ids including `account.id`.

  ## Examples

      iex> Logistiki.VirtualAccounts.ancestor_ids(nostro_account)
      [4, 3, 2, 1]
  """
  @doc since: "0.1.0"
  @spec ancestor_ids(VirtualAccount.t()) :: [integer()]
  def ancestor_ids(%VirtualAccount{id: id}) do
    Repo.all(from(c in VirtualAccountClosure, where: c.descendant_id == ^id, select: c.ancestor_id))
  end

  @doc """
  True when the account is a leaf (has no children). Roots are aggregation
  nodes and are not leaves.

  ## Arguments

    * `account` — `%VirtualAccount{}`.

  ## Returns

    * `boolean()` — `true` if the account has no children, `false` otherwise.

  ## Examples

      iex> Logistiki.VirtualAccounts.leaf?(nostro_account)
      true

      iex> Logistiki.VirtualAccounts.leaf?(assets_root)
      false
  """
  @doc since: "0.1.0"
  @spec leaf?(VirtualAccount.t()) :: boolean()
  def leaf?(%VirtualAccount{id: id}) do
    from(a in VirtualAccount, where: a.parent_id == ^id) |> Repo.exists?() |> Kernel.not()
  end

  @doc """
  True when the account accepts postings — i.e. `posting_allowed: true` and
  `status: "active"`.

  ## Arguments

    * `account` — `%VirtualAccount{}` or any term.

  ## Returns

    * `boolean()` — `true` only when `posting_allowed == true` and
      `status == "active"`.

  ## Examples

      iex> Logistiki.VirtualAccounts.posting_account?(nostro_account)
      true

      iex> Logistiki.VirtualAccounts.posting_account?(assets_root)
      false

      iex> Logistiki.VirtualAccounts.posting_account?(%{posting_allowed: true, status: "frozen"})
      false
  """
  @doc since: "0.1.0"
  @spec posting_account?(VirtualAccount.t()) :: boolean()
  def posting_account?(%VirtualAccount{posting_allowed: true, status: "active"}), do: true

  def posting_account?(_), do: false
end
