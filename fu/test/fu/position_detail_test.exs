defmodule Fu.PositionDetailTest do
  @moduledoc """
  Model: the player sets a DEFAULT sub-position per main position
  (DEF/MID/FWD — GK has no variant) in their profile. Which main position
  they play is still chosen on the home screen (the quick swap) and is the
  only thing matchmaking sees. The sub is pure display: it relabels the
  position the player picked. Hard invariant unchanged — the engine speaks
  the main 4 only.
  """
  use Fu.DataCase, async: true

  alias Fu.{Accounts, Positions, Queues}
  alias Fu.Accounts.Player

  describe "Positions" do
    test "main 4 intact; GK has a single variant, the rest are real subs" do
      assert Positions.positions() == ~w(GK DEF MID FWD)
      assert Positions.subs_for("GK") == [{"GK", "Goalkeeper"}]
      assert {"LB", "Left Back"} in Positions.subs_for("DEF")
      assert Positions.sub_abbrs("MID") == ~w(CDM CM CAM LM RM)
      assert Positions.group_label("FWD") == "Forwards"
    end
  end

  describe "Accounts.sub_label/2 — relabel a main with the player's default" do
    test "uses the per-main default, falls back to the main label, GK is always GK" do
      p =
        player_fixture()
        |> Ecto.Changeset.change(def_sub: "CB", mid_sub: "CDM")
        |> Fu.Repo.update!()

      assert Accounts.sub_label(p, "DEF") == "CB"
      assert Accounts.sub_label(p, "MID") == "CDM"
      assert Accounts.sub_label(p, "FWD") == "FWD"
      assert Accounts.sub_label(p, "GK") == "GK"
    end
  end

  describe "profile_changeset/2 — set a default sub per main" do
    setup do: %{p: player_fixture()}

    test "accepts a valid sub for each main", %{p: p} do
      assert {:ok, s} =
               Accounts.update_profile(p, %{
                 "display_name" => "X",
                 "def_sub" => "LB",
                 "mid_sub" => "CDM",
                 "fwd_sub" => "ST"
               })

      assert {s.def_sub, s.mid_sub, s.fwd_sub} == {"LB", "CDM", "ST"}
    end

    test "all sub defaults are optional (blank ok)", %{p: p} do
      assert {:ok, s} = Accounts.update_profile(p, %{"display_name" => "X", "def_sub" => ""})
      assert s.def_sub in [nil, ""]
    end

    test "rejects a sub that belongs to a different main", %{p: p} do
      cs = Player.profile_changeset(p, %{"display_name" => "X", "def_sub" => "CDM"})
      refute cs.valid?
      assert errors_on(cs)[:def_sub]
    end

    test "rejects an unknown sub", %{p: p} do
      cs = Player.profile_changeset(p, %{"display_name" => "X", "fwd_sub" => "ZZ"})
      refute cs.valid?
      assert errors_on(cs)[:fwd_sub]
    end

    test "setting sub defaults does not change the main position the engine uses", %{p: p} do
      {:ok, s} =
        Accounts.update_profile(p, %{"display_name" => "X", "def_sub" => "CB"})

      assert s.primary_position == p.primary_position
    end
  end

  test "INVARIANT: sub defaults never reach matchmaking" do
    p =
      player_fixture(primary_position: "DEF")
      |> Ecto.Changeset.change(def_sub: "CB")
      |> Fu.Repo.update!()

    q = queue_fixture(format: "8v8")
    assert Queues.pick_position(q, p) == "DEF"
    {:ok, m} = Queues.join(q, p)
    assert m.declared_position == "DEF"
  end
end
