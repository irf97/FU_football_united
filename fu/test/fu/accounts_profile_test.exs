defmodule Fu.AccountsProfileTest do
  @moduledoc "Profile identity additions: nickname, nation, birthdate→age; playstyle dropped."
  use Fu.DataCase, async: true

  alias Fu.Accounts
  alias Fu.Accounts.Player

  describe "age/1" do
    test "is nil when no birthdate" do
      assert Accounts.age(%Player{birthdate: nil}) == nil
    end

    test "computes full years, accounting for whether the birthday passed this year" do
      today = Date.utc_today()

      had_birthday = %Player{birthdate: %{today | year: today.year - 25}}
      assert Accounts.age(had_birthday) == 25

      # Birthday is tomorrow → still one year younger.
      tomorrow = Date.add(today, 1)
      not_yet = %Player{birthdate: %{tomorrow | year: tomorrow.year - 30}}
      assert Accounts.age(not_yet) == 29
    end
  end

  describe "profile_changeset/2 — new identity fields" do
    setup do
      p = player_fixture()
      %{p: p}
    end

    test "accepts nickname, nation and birthdate", %{p: p} do
      attrs = %{
        "display_name" => "Irfan",
        "primary_detail" => "CM",
        "nickname" => "The Wall",
        "nation" => "Netherlands",
        "birthdate" => "1998-04-12"
      }

      assert {:ok, saved} = Accounts.update_profile(p, attrs)
      assert saved.nickname == "The Wall"
      assert saved.nation == "Netherlands"
      assert saved.birthdate == ~D[1998-04-12]
    end

    test "rejects a birthdate in the future", %{p: p} do
      future = Date.utc_today() |> Date.add(365) |> Date.to_iso8601()

      cs =
        Player.profile_changeset(p, %{
          "display_name" => "X",
          "primary_detail" => "CM",
          "birthdate" => future
        })

      refute cs.valid?
      assert errors_on(cs)[:birthdate]
    end

    test "rejects an unknown nation", %{p: p} do
      cs =
        Player.profile_changeset(p, %{
          "display_name" => "X",
          "primary_detail" => "CM",
          "nation" => "Wakanda"
        })

      refute cs.valid?
      assert errors_on(cs)[:nation]
    end

    test "no longer casts playstyle (field removed from profile)", %{p: p} do
      cs =
        Player.profile_changeset(p, %{
          "display_name" => "X",
          "primary_detail" => "CM",
          "playstyle" => "Aggressive"
        })

      refute Map.has_key?(cs.changes, :playstyle)
    end
  end
end
