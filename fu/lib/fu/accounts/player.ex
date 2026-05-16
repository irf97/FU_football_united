defmodule Fu.Accounts.Player do
  use Ecto.Schema
  import Ecto.Changeset

  @positions Fu.Positions.positions()
  @playstyles ~w(Aggressive Possession Counter Defensive Box-to-box Playmaker Finisher)

  schema "players" do
    field :phone, :string
    field :display_name, :string
    field :avatar_url, :string
    field :jersey_number, :integer, default: 10
    field :home_lat, :float
    field :home_lng, :float
    field :home_label, :string
    field :rank, :float, default: 50.0
    field :playstyle, :string
    field :primary_position, :string, default: "MID"
    field :secondary_position, :string
    field :fill_mode, :boolean, default: false
    field :queue_region_km, :integer, default: 25
    field :avatar_legend, :string, default: "Pelé"
    field :avatar_kit, :string, default: "Custom"
    field :avatar_color, :string, default: "#67e8f9"
    field :is_admin, :boolean, default: false
    field :suspended_until, :utc_datetime
    field :last_played_at, :utc_datetime
    field :skip_streak, :integer, default: 0

    has_many :availability_windows, Fu.Accounts.AvailabilityWindow
    timestamps(type: :utc_datetime)
  end

  @doc "Created at first OTP verification — only phone is known."
  def registration_changeset(player, attrs) do
    player
    |> cast(attrs, [:phone, :display_name])
    |> validate_required([:phone])
    |> put_default_name()
    |> validate_format(:phone, ~r/^\+?[0-9]{7,15}$/, message: "invalid phone")
    |> unique_constraint(:phone)
  end

  @doc "Profile edits: identity + position prefs (spec §2.6)."
  def profile_changeset(player, attrs) do
    player
    |> cast(attrs, [
      :display_name,
      :avatar_url,
      :jersey_number,
      :home_lat,
      :home_lng,
      :home_label,
      :playstyle,
      :primary_position,
      :secondary_position,
      :fill_mode,
      :queue_region_km,
      :avatar_legend,
      :avatar_kit,
      :avatar_color
    ])
    |> validate_required([:display_name, :primary_position])
    |> validate_inclusion(:primary_position, @positions)
    |> validate_inclusion(:secondary_position, @positions ++ [nil, ""])
    |> validate_inclusion(:playstyle, @playstyles ++ [nil, ""])
    |> validate_number(:jersey_number, greater_than_or_equal_to: 1, less_than_or_equal_to: 99)
    |> validate_number(:queue_region_km, greater_than: 0, less_than_or_equal_to: 200)
    |> validate_format(:avatar_color, ~r/^#[0-9a-fA-F]{6}$/, message: "must be a hex colour")
    |> validate_secondary_differs()
  end

  defp put_default_name(changeset) do
    case get_field(changeset, :display_name) do
      nil ->
        phone = get_field(changeset, :phone) || ""
        put_change(changeset, :display_name, "Player " <> String.slice(phone, -4, 4))

      _ ->
        changeset
    end
  end

  defp validate_secondary_differs(changeset) do
    primary = get_field(changeset, :primary_position)
    secondary = get_field(changeset, :secondary_position)

    if secondary not in [nil, ""] and secondary == primary do
      add_error(changeset, :secondary_position, "must differ from primary")
    else
      changeset
    end
  end
end
