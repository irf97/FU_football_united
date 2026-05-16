defmodule Fu.FriendsTest do
  @moduledoc "Friend add/invite/accept/decline (spec §2.12) — now UI-reachable."
  use Fu.DataCase, async: true

  alias Fu.Friends

  test "request_by_phone sends a pending request the target can see" do
    a = player_fixture()
    b = player_fixture()

    assert {:ok, _} = Friends.request_by_phone(a, b.phone)
    assert [req] = Friends.pending_incoming(b)
    assert req.requester_id == a.id
    assert [out] = Friends.pending_outgoing(a)
    assert out.addressee_id == b.id
    refute Friends.friends?(a, b)
  end

  test "accepting makes them friends both directions" do
    a = player_fixture()
    b = player_fixture()
    {:ok, _} = Friends.request_by_phone(a, b.phone)
    [req] = Friends.pending_incoming(b)

    assert {:ok, _} = Friends.accept_friend(req.id)
    assert Friends.friends?(a, b)
    assert Friends.friends?(b, a)
    assert a.id in Enum.map(Friends.list_friends(b), & &1.id)
    assert Friends.pending_incoming(b) == []
  end

  test "a reverse request auto-accepts instead of duplicating" do
    a = player_fixture()
    b = player_fixture()
    {:ok, _} = Friends.request_by_phone(a, b.phone)
    assert {:ok, _} = Friends.request_by_phone(b, a.phone)
    assert Friends.friends?(a, b)
  end

  test "decline removes the pending request" do
    a = player_fixture()
    b = player_fixture()
    {:ok, _} = Friends.request_by_phone(a, b.phone)
    [req] = Friends.pending_incoming(b)

    assert {:ok, _} = Friends.decline_friend(req.id)
    assert Friends.pending_incoming(b) == []
    refute Friends.friends?(a, b)
  end

  test "error paths: not_found / self / already_friends / already_requested" do
    a = player_fixture()
    b = player_fixture()

    assert {:error, :not_found} = Friends.request_by_phone(a, "+31600000000")
    assert {:error, :self} = Friends.request_by_phone(a, a.phone)

    {:ok, _} = Friends.request_by_phone(a, b.phone)
    assert {:error, :already_requested} = Friends.request_by_phone(a, b.phone)

    [req] = Friends.pending_incoming(b)
    {:ok, _} = Friends.accept_friend(req.id)
    assert {:error, :already_friends} = Friends.request_by_phone(a, b.phone)
  end
end
