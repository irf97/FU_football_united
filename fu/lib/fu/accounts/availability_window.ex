defmodule Fu.Accounts.AvailabilityWindow do
  use Ecto.Schema
  import Ecto.Changeset

  schema "availability_windows" do
    field :kind, :string, default: "recurring"
    field :weekday, :integer
    field :date, :date
    field :start_time, :time
    field :end_time, :time

    belongs_to :player, Fu.Accounts.Player
    timestamps(type: :utc_datetime)
  end

  def changeset(window, attrs) do
    window
    |> cast(attrs, [:kind, :weekday, :date, :start_time, :end_time, :player_id])
    |> validate_required([:kind, :start_time, :end_time, :player_id])
    |> validate_inclusion(:kind, ~w(recurring oneoff))
    |> validate_window_kind()
    |> validate_time_order()
  end

  defp validate_window_kind(changeset) do
    case get_field(changeset, :kind) do
      "recurring" ->
        changeset
        |> validate_required([:weekday])
        |> validate_inclusion(:weekday, 0..6)

      "oneoff" ->
        validate_required(changeset, [:date])

      _ ->
        changeset
    end
  end

  defp validate_time_order(changeset) do
    s = get_field(changeset, :start_time)
    e = get_field(changeset, :end_time)

    if s && e && Time.compare(e, s) != :gt do
      add_error(changeset, :end_time, "must be after start time")
    else
      changeset
    end
  end
end
