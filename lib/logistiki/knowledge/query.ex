defmodule Logistiki.Knowledge.Query do
  @moduledoc """
  Helpers for querying materialized `ExDatalog.Knowledge` for Logistiki facts.

  The event under evaluation is always identified by the atom `:evt` inside the
  Datalog program (see `Logistiki.Knowledge.Facts.event_id/0`).
  """

  alias ExDatalog.Knowledge
  alias Logistiki.Knowledge.Facts

  @doc "Returns all derived `policy` facts for the current event."
  def policies(knowledge) do
    knowledge
    |> Knowledge.get("policy")
    |> Enum.filter(fn {evt, _policy} -> evt == Facts.event_id() end)
    |> Enum.map(fn {_evt, policy} -> policy end)
  end

  @doc "True when the event is blocked by a business rule."
  def blocked?(knowledge) do
    target = {Facts.event_id()}

    Knowledge.get(knowledge, "blocked")
    |> Enum.any?(&(&1 == target))
  end

  @doc "True when the event requires approval."
  def requires_approval?(knowledge) do
    target = {Facts.event_id()}

    Knowledge.get(knowledge, "requires_approval")
    |> Enum.any?(&(&1 == target))
  end

  @doc "Returns all resolved `account_role` facts for the current event."
  def account_roles(knowledge) do
    knowledge
    |> Knowledge.get("account_role")
    |> Enum.filter(fn {evt, _role, _code} -> evt == Facts.event_id() end)
    |> Enum.into(%{}, fn {_evt, role, code} -> {role, code} end)
  end

  @doc "Returns all `template_posting` facts (for every policy)."
  def template_postings(knowledge) do
    Knowledge.get(knowledge, "template_posting")
    |> Enum.map(fn {policy, seq, direction, role, amount_var, currency_var} ->
      %{
        policy: policy,
        sequence: seq,
        direction: direction,
        role: role,
        amount_var: amount_var,
        currency_var: currency_var
      }
    end)
  end

  @doc "Returns all `requires_dimension` facts (for every policy)."
  def required_dimensions(knowledge) do
    Knowledge.get(knowledge, "requires_dimension")
    |> Enum.into(%{}, fn {policy, dimension} -> {policy, dimension} end)
    |> Enum.group_by(fn {policy, _dim} -> policy end, fn {_policy, dim} -> dim end)
  end
end
