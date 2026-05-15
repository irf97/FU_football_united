defmodule Fu.Repo do
  use Ecto.Repo,
    otp_app: :fu,
    adapter: Ecto.Adapters.Postgres
end
