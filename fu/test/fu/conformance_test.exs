defmodule Fu.ConformanceTest do
  @moduledoc """
  The reference, checked against its own published contract.

  Loads `conformance/vectors.json` and *independently re-derives* every
  value through the primitives — a different code path than the generator.
  If they disagree, the contract drifted: fail loudly. This is exactly the
  harness the Rust runtime must implement (see conformance/README.md); here
  it doubles as a regression gate and a worked porting example.
  """
  use ExUnit.Case, async: true

  alias Fu.Mesh.{Identity, V3, Wire}

  setup_all do
    json = File.read!(Path.join(File.cwd!(), "conformance/vectors.json"))
    {:ok, doc: Jason.decode!(json)}
  end

  defp hx(b), do: Base.encode16(b, case: :lower)
  defp unhex(s), do: Base.decode16!(s, case: :lower)

  test "spec + version handshake (step 0 — refuse anything else)", %{doc: d} do
    assert d["spec"] == "fu-mesh-conformance"
    assert d["version"] == 3
  end

  test "identity vectors reproduce exactly", %{doc: d} do
    for v <- d["identity"] do
      {pub, priv} = Identity.keypair_from_seed(unhex(v["seed_hex"]))
      assert hx(pub) == v["public_hex"]
      assert Identity.address(pub) == v["address"]

      if p = v["sign_payload"] do
        assert hx(Identity.sign(priv, p)) == v["signature_hex"]
      end
    end
  end

  test "canonical encoding + signatures reproduce exactly", %{doc: d} do
    {_pub, priv} = Identity.keypair_from_seed(unhex(hd(d["identity"])["seed_hex"]))

    for c <- d["canonical_attestations"] do
      att = V3.attest(c["match"], c["player"], c["delta"], [])
      assert Identity.canonical(att) == c["canonical"]
      assert hx(Identity.sign(priv, c["canonical"])) == c["signature_hex"]
    end
  end

  test "mesh.signed_ingest reproduces exactly", %{doc: d} do
    m = d["mesh"]["signed_ingest"]
    {pub, priv} = Identity.keypair_from_seed(unhex(hd(d["identity"])["seed_hex"]))

    att = V3.attest(1, "p", 1.5, []) |> Identity.sign_attest(priv, pub)
    w1 = V3.new_node("w1", ["p"]) |> V3.ingest_signed(att)
    w2 = V3.new_node("w2", ["p"]) |> V3.ingest_signed(att)
    w3 = V3.new_node("w3", ["p"]) |> V3.ingest_signed(%{att | delta: 99.0})
    nodes = %{"w1" => w1, "w2" => w2, "p" => V3.new_node("p", [])}

    assert_in_delta V3.rank(w1, "p"), m["valid_att_rank"], 1.0e-9
    assert V3.knows?(w3, "p") == m["forged_att_known"]
    assert_in_delta V3.witnessed_rank(nodes, ["w1", "w2"], "p"),
                    m["witnessed_rank_friends"],
                    1.0e-9
  end

  test "bootstrap (provisional witnesses) reproduces exactly", %{doc: d} do
    b = d["bootstrap"]
    a = V3.attest(1, "orphan", 1.5, [])

    acq = fn id ->
      V3.new_node(id, [])
      |> then(&Enum.reduce(1..V3.acq_threshold(), &1, fn _, x -> V3.met(x, "orphan") end))
      |> V3.ingest(a)
    end

    nodes = %{
      "o1" => acq.("o1"),
      "o2" => acq.("o2"),
      "orphan" => V3.new_node("orphan", []) |> V3.ingest(a)
    }

    assert Enum.sort(V3.provisional_witnesses(nodes, "orphan")) == b["provisional_witnesses"]
    assert_in_delta V3.recoverable_rank(nodes, [], "orphan"),
                    b["recoverable_rank_no_friends"],
                    1.0e-9
    assert ("orphan" not in V3.provisional_witnesses(nodes, "orphan")) == b["self_excluded"]
  end

  test "wire frame reproduces byte-exact, decodes, and chunks identically", %{doc: d} do
    w = d["wire"]
    {pub, priv} = Identity.keypair_from_seed(unhex(w["signer_seed_hex"]))
    a = w["attestation"]

    att =
      V3.attest(a["match"], a["player"], a["delta"], a["witnesses"])
      |> Identity.sign_attest(priv, pub)

    frame = Wire.encode(att)
    assert hx(frame) == w["frame_hex"]
    assert byte_size(frame) == w["frame_bytes"]

    assert {:ok, got, ""} = Wire.decode(unhex(w["frame_hex"]))
    assert Identity.verified?(got)
    assert got.player == a["player"]

    mx = w["mtu_example"]
    assert length(Wire.chunks(frame, mx["mtu"])) == mx["chunk_count"]
  end
end
