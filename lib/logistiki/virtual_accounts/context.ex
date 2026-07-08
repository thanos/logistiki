defmodule Logistiki.VirtualAccounts do
  @moduledoc """
  The context for hierarchical virtual accounts.

  Virtual accounts represent accounting accounts and account-like projections.
  They form a tree maintained through a closure table
  (`Logistiki.VirtualAccounts.VirtualAccountClosure`).

  Rules enforced here:

    * account code is unique
    * only leaf accounts may allow postings
    * posting accounts require a currency
    * aggregation accounts may have a nil currency
    * cycles are forbidden (the closure table is rewritten on move)
  """

  import Ecto.Query

  alias Logistiki.Repo
  alias Logistiki.VirtualAccounts.VirtualAccount
  alias Logistiki.VirtualAccounts.VirtualAccountClosure

  @doc "Creates a new virtual account."
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

  defp ensure_parent_allows_children(nil), do: :ok

  defp ensure_parent_allows_children(parent_id) do
    case Repo.get(VirtualAccount, parent_id) do
      nil -> {:error, :parent_not_found}
      %VirtualAccount{posting_allowed: true} -> {:error, :parent_is_posting_account}
      %VirtualAccount{} -> :ok
    end
  end

  @doc "Updates a virtual account's mutable attributes (not its parent)."
  def update_account(%VirtualAccount{} = account, attrs) do
    account
    |> VirtualAccount.changeset(attrs)
    |> Ecto.Changeset.change()
    |> Repo.update()
  end

  @doc "Fetches a single account by id, raising if not found."
  def get_account!(id), do: Repo.get!(VirtualAccount, id)

  @doc "Fetches a single account by code, raising if not found."
  def get_account_by_code!(code) do
    Repo.get_by!(VirtualAccount, code: code)
  end

  @doc "Fetches a single account by code, returning `{:ok, account}` or `{:error, :not_found}`."
  def get_account_by_code(code) do
    case Repo.get_by(VirtualAccount, code: code) do
      nil -> {:error, :not_found}
      account -> {:ok, account}
    end
  end

  @doc "Fetches a single account, returning `{:ok, account}` or `{:error, :not_found}`."
  def get_account(id) do
    case Repo.get(VirtualAccount, id) do
      nil -> {:error, :not_found}
      account -> {:ok, account}
    end
  end

  @doc "Resolves an account from either a `%VirtualAccount{}`, an id, or an account code."
  def resolve(%VirtualAccount{} = account), do: {:ok, account}

  def resolve(code) when is_binary(code) do
    case get_account_by_code(code) do
      {:ok, account} -> {:ok, account}
      {:error, :not_found} -> resolve_by_id(code)
    end
  end

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

  @doc "Lists accounts, optionally filtered by `:status`, `:account_type`, `:currency`, or `:parent_id`."
  def list_accounts(opts \\ []) do
    VirtualAccount
    |> maybe_filter(:status, opts)
    |> maybe_filter(:account_type, opts)
    |> maybe_filter(:currency, opts)
    |> maybe_filter(:parent_id, opts)
    |> order_by([a], asc: a.code)
    |> Repo.all()
  end

  defp maybe_filter(query, key, opts) do
    case Keyword.get(opts, key) do
      nil -> query
      value -> where(query, [a], field(a, ^key) == ^value)
    end
  end

  @doc "Lists direct children of `account`."
  def list_children(%VirtualAccount{id: id}) do
    Repo.all(from a in VirtualAccount, where: a.parent_id == ^id, order_by: [asc: a.code])
  end

  @doc "Lists all descendants of `account` (excluding the account itself)."
  def list_descendants(%VirtualAccount{id: id}) do
    descendants_query(id)
    |> order_by([a], asc: a.code)
    |> Repo.all()
  end

  @doc "Lists all ancestors of `account` ordered from nearest to farthest."
  def list_ancestors(%VirtualAccount{id: id}) do
    ancestors_query(id)
    |> order_by([a, c], asc: c.depth)
    |> Repo.all()
  end

  @doc "Moves `account` under `new_parent` (which may be `nil` for a root), rewriting the closure."
  def move_account(%VirtualAccount{} = account, new_parent) do
    new_parent_id = parent_id_from(new_parent)

    if creates_cycle?(account.id, new_parent_id) do
      {:error, :cycle_detected}
    else
      Repo.transaction(fn -> perform_move(account, new_parent_id) end)
    end
  end

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

  defp parent_id_from(nil), do: nil
  defp parent_id_from(%VirtualAccount{id: id}), do: id
  defp parent_id_from(id) when is_binary(id), do: id

  defp creates_cycle?(_id, nil), do: false

  defp creates_cycle?(id, new_parent_id) do
    # Moving id under new_parent creates a cycle if id is already an ancestor
    # of new_parent (or equal to it).
    from(c in VirtualAccountClosure,
      where: c.ancestor_id == ^id and c.descendant_id == ^new_parent_id
    )
    |> Repo.exists?()
  end

  @doc false
  def insert_closure_for(%VirtualAccount{id: id, parent_id: nil}) do
    insert_self_closure(id)
    {:ok, :root}
  end

  def insert_closure_for(%VirtualAccount{id: id, parent_id: parent_id}) do
    insert_self_closure(id)
    insert_inherited_closure(id, parent_id)
    {:ok, :child}
  end

  defp insert_self_closure(id) do
    Repo.insert_all(
      VirtualAccountClosure,
      [%{ancestor_id: id, descendant_id: id, depth: 0, inserted_at: DateTime.utc_now(:second)}]
    )
  end

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

  defp link_subtree_under_new_parent(%VirtualAccount{id: id, parent_id: nil}) do
    insert_self_closure(id)
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

  defp descendants_query(id) do
    from a in VirtualAccount,
      join: c in VirtualAccountClosure, on: c.descendant_id == a.id,
      where: c.ancestor_id == ^id and c.depth > 0
  end

  defp ancestors_query(id) do
    from a in VirtualAccount,
      join: c in VirtualAccountClosure, on: c.ancestor_id == a.id,
      where: c.descendant_id == ^id and c.depth > 0
  end

  @doc "Returns the ids of all descendants of `account` (including itself)."
  def descendant_ids(%VirtualAccount{id: id}) do
    Repo.all(from c in VirtualAccountClosure, where: c.ancestor_id == ^id, select: c.descendant_id)
  end

  @doc "Returns the ids of all ancestors of `account` (including itself)."
  def ancestor_ids(%VirtualAccount{id: id}) do
    Repo.all(from c in VirtualAccountClosure, where: c.descendant_id == ^id, select: c.ancestor_id)
  end

  @doc "True when the account is a leaf (has no children). Roots are aggregation nodes."
  def leaf?(%VirtualAccount{id: id}) do
    from(a in VirtualAccount, where: a.parent_id == ^id) |> Repo.exists?() |> Kernel.not()
  end

  @doc "True when the account accepts postings."
  def posting_account?(%VirtualAccount{posting_allowed: true, status: "active"}), do: true

  def posting_account?(_), do: false
end
