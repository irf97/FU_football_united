defmodule FuWeb.ReturnPathTest do
  use ExUnit.Case, async: true
  alias FuWeb.ReturnPath

  test "known read-only destinations retain their query strings" do
    for path <- [
          "/explore?category=music&q=guitar%20night",
          "/hobbies",
          "/hobbies/new?hobby=birdwatching",
          "/hobbies/42?from=invite",
          "/hobbies/42/assistant",
          "/equipment",
          "/profile",
          "/admin",
          "/queue/3/chat",
          "/lobby/3",
          "/match/3",
          "/postmatch/3",
          "/browse",
          "/queue",
          "/lab"
        ] do
      assert ReturnPath.safe(path) == path
    end
  end

  test "anonymous site entry starts in shared discovery" do
    assert ReturnPath.safe("/") == "/explore"
    assert ReturnPath.safe("/?from=bookmark") == "/explore"
  end

  test "invalid, external, nested-auth and oversized destinations fall back to Explore" do
    for path <- [
          nil,
          [],
          %{},
          "https://outside.example/hobbies/1",
          "//outside.example/hobbies/1",
          "/\\outside.example",
          "/%2foutside.example",
          "/explore\r\nLocation: https://outside.example",
          "/explore\0",
          "/explore#outside",
          "/session/token",
          "/session",
          "/login",
          "/api/equipment/observations",
          "/unknown",
          "/hobbies/../admin",
          "/hobbies/not-an-id",
          "/hobbies/0",
          "/hobbies/" <> String.duplicate("1", 20),
          "/explore?q=" <> String.duplicate("x", 2048)
        ] do
      assert ReturnPath.safe(path) == "/explore"
    end
  end
end
