defmodule Fu.Mesh.IdentityTest do
  @moduledoc """
  Protocol-grade identity: real Ed25519 keypairs, signed content-addressed
  attestations, verify-on-receive. Makes the mesh model a faithful
  reference, not an abstraction — an unverifiable event is not state.
  """
  use ExUnit.Case, async: true

  alias Fu.Mesh.Identity
  alias Fu.Mesh.V3

  test "a keypair signs and verifies its own payload" do
    {pub, priv} = Identity.keypair()
    msg = "match:42|player:p|delta:1.5"
    sig = Identity.sign(priv, msg)

    assert Identity.verify(pub, msg, sig)
  end

  test "a tampered payload fails verification" do
    {pub, priv} = Identity.keypair()
    sig = Identity.sign(priv, "delta:1.5")
    refute Identity.verify(pub, "delta:99.0", sig)
  end

  test "the wrong key fails verification" do
    {_pub, priv} = Identity.keypair()
    {other_pub, _} = Identity.keypair()
    sig = Identity.sign(priv, "x")
    refute Identity.verify(other_pub, "x", sig)
  end

  test "address/1 is a stable short content-addressed id of the public key" do
    {pub, _} = Identity.keypair()
    assert Identity.address(pub) == Identity.address(pub)
    assert is_binary(Identity.address(pub))
    {pub2, _} = Identity.keypair()
    refute Identity.address(pub) == Identity.address(pub2)
  end

  describe "signed attestations in the mesh" do
    test "a validly signed attestation is accepted and folded" do
      {pub, priv} = Identity.keypair()
      att = V3.attest(1, "p", 1.5, []) |> Identity.sign_attest(priv, pub)

      assert Identity.verified?(att)
      node = V3.new_node("w", ["p"]) |> V3.ingest_signed(att)
      assert_in_delta V3.rank(node, "p"), 51.5, 1.0e-9
    end

    test "a forged (tampered) signed attestation is dropped, never folded" do
      {pub, priv} = Identity.keypair()
      att = V3.attest(1, "p", 1.5, []) |> Identity.sign_attest(priv, pub)
      forged = %{att | delta: 99.0}

      refute Identity.verified?(forged)
      node = V3.new_node("w", ["p"]) |> V3.ingest_signed(forged)
      assert V3.rank(node, "p") == 50.0
      refute V3.knows?(node, "p")
    end

    test "an attestation whose author key doesn't match its signature is dropped" do
      {pub, priv} = Identity.keypair()
      {other_pub, _} = Identity.keypair()
      att = V3.attest(2, "p", 0.3, []) |> Identity.sign_attest(priv, pub)
      swapped = %{att | author_pub: other_pub}

      refute Identity.verified?(swapped)
      node = V3.new_node("w", ["p"]) |> V3.ingest_signed(swapped)
      assert V3.rank(node, "p") == 50.0
    end
  end
end
