defmodule Fu.ExperienceTest do
  use Fu.DataCase, async: true
  alias Fu.Accounts

  test "experience preferences are independent of football profile and authority" do
    player = player_fixture()

    assert {:ok, saved} =
             apply(Accounts, :update_experience, [player, %{
               "main_hobby" => "  Guitar  ", "experience_theme" => "auto",
               "is_admin" => "true", "rank" => "999", "primary_position" => "GK"
             }])

    assert Map.get(saved, :main_hobby) == "guitar"
    assert Map.get(saved, :experience_theme) == "auto"
    assert saved.rank == player.rank
    assert saved.primary_position == player.primary_position
    refute saved.is_admin
  end

  test "an arbitrary hobby has a neutral experience and explicit themes win" do
    resolve = fn attrs -> apply(Fu.Experiences, :for_player, [attrs]) end
    assert resolve.(%{main_hobby: "futsal", experience_theme: "auto"}).key == "football"
    assert resolve.(%{main_hobby: "guitar", experience_theme: "auto"}).key == "music"
    assert resolve.(%{main_hobby: "table tennis", experience_theme: "auto"}).key == "court"
    assert resolve.(%{main_hobby: "unlisted hobby", experience_theme: "auto"}).key == "spontaan"
    assert resolve.(%{main_hobby: "futsal", experience_theme: "outdoors"}).key == "outdoors"
    assert resolve.(nil).key == "spontaan"
    assert resolve.(%{main_hobby: "guitar", experience_theme: "untrusted"}).key == "spontaan"
  end

  test "unknown themes and oversized hobbies are rejected" do
    player = player_fixture()
    assert {:error, cs} = apply(Accounts, :update_experience, [player, %{experience_theme: "injected"}])
    assert errors_on(cs)[:experience_theme]
    assert {:error, cs} = apply(Accounts, :update_experience, [player, %{main_hobby: String.duplicate("x", 61)}])
    assert errors_on(cs)[:main_hobby]
  end
end
