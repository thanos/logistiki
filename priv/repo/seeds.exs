# priv/repo/seeds.exs
#
# Seeds the Logistiki demo scenario: business entity tree, virtual account
# tree, and entity-account relationships. Run with `mix ecto.setup` or
# `mix run priv/repo/seeds.exs`.

alias Logistiki.Demo.Seeds
alias Logistiki.Repo

# Only seed if the entity table is empty (idempotent).
if Repo.aggregate(Logistiki.BusinessEntities.BusinessEntity, :count) == 0 do
  {entities, accounts} = Seeds.run()

  IO.puts("Seeded Logistiki demo:")
  IO.puts("  #{map_size(entities)} business entities")
  IO.puts("  #{map_size(accounts)} virtual accounts")
else
  IO.puts("Logistiki demo already seeded; skipping.")
end
