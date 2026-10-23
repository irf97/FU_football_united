defmodule Fu.Hobbies.Session do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hobby_sessions" do
    field :title, :string
    field :hobby, :string
    field :category, :string, default: "other"
    field :kind, :string, default: "session"
    field :mode, :string, default: "open"
    field :place, :string
    field :access_status, :string, default: "pending"
    field :access_note, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :capacity, :integer
    field :min_participants, :integer, default: 1
    field :status, :string, default: "scheduled"
    field :cancellation_reason, :string
    belongs_to :host, Fu.Accounts.Player
    has_many :participants, Fu.Hobbies.Participant
    timestamps(type: :utc_datetime)
  end

  def creation_changeset(session, attrs) do
    session
    |> cast(attrs, [
      :title,
      :hobby,
      :category,
      :kind,
      :mode,
      :place,
      :starts_at,
      :ends_at,
      :capacity,
      :min_participants
    ])
    |> update_change(:title, &String.trim/1)
    |> update_change(:hobby, &(String.trim(&1) |> String.downcase()))
    |> update_change(:place, &String.trim/1)
    |> validate_required([
      :title,
      :hobby,
      :category,
      :kind,
      :mode,
      :place,
      :starts_at,
      :ends_at,
      :capacity,
      :min_participants
    ])
    |> validate_length(:title, max: 120)
    |> validate_length(:hobby, max: 60)
    |> validate_length(:place, max: 200)
    |> validate_inclusion(:mode, ["open", "practice", "committed"])
    |> validate_inclusion(:category, Fu.Hobbies.Discovery.category_codes())
    |> validate_inclusion(:kind, Fu.Hobbies.Discovery.kind_codes())
    |> validate_number(:capacity, greater_than: 0, less_than_or_equal_to: 1000)
    |> validate_number(:min_participants, greater_than: 0)
    |> validate_window()
    |> foreign_key_constraint(:host_id)
    |> check_constraint(:capacity, name: :hobby_sessions_capacity_bounds)
    |> check_constraint(:min_participants, name: :hobby_sessions_minimum_bounds)
    |> check_constraint(:category, name: :hobby_category_valid)
    |> check_constraint(:kind, name: :hobby_kind_valid)
  end

  defp validate_window(changeset) do
    start = get_field(changeset, :starts_at)
    finish = get_field(changeset, :ends_at)
    capacity = get_field(changeset, :capacity)
    minimum = get_field(changeset, :min_participants)

    changeset =
      if is_integer(capacity) and is_integer(minimum) and minimum > capacity,
        do: add_error(changeset, :min_participants, "cannot exceed capacity"),
        else: changeset

    changeset =
      if match?(%DateTime{}, start) and DateTime.compare(start, DateTime.utc_now()) != :gt,
        do: add_error(changeset, :starts_at, "must be in the future"),
        else: changeset

    if match?(%DateTime{}, start) and match?(%DateTime{}, finish) and
         DateTime.compare(finish, start) != :gt,
       do: add_error(changeset, :ends_at, "must be after the start"),
       else: changeset
  end
end
