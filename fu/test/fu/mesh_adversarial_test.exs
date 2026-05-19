defmodule Fu.Mesh.AdversarialTest do
  @moduledoc """
  The security boundary, made explicit and contract-locked.

    * a *minority* of colluding witnesses CANNOT move the witnessed median;
    * a *majority* CAN (this is the honest, stated limit — group-collusion);
    * a byzantine relay that mangles in transit cannot inject false rank
      (verify-or-drop) — it can only withhold (availability, not integrity);
    * a partition heals: the cut-off side converges once a bridge relays.
  """
  use ExUnit.Case, async: true

  alias Fu.Mesh.{Identity, V3, Wire}

  defp keys(seed), do: Identity.keypair_from_seed(:binary.copy(<<seed>>, 32))

  setup do
    {hp, hpriv} = keys(20)
    {cp, cpriv} = keys(21)
    honest = V3.attest(1, "P", 1.5, []) |> Identity.sign_attest(hpriv, hp)
    # A colluding signer signs a wildly inflated, *validly-signed* fact.
    collude = V3.attest(2, "P", 50.0, []) |> Identity.sign_attest(cpriv, cp)
    %{honest: honest, collude: collude}
  end

  defp witness(id, atts), do: Enum.reduce(atts, V3.new_node(id, ["P"]), &V3.ingest_signed(&2, &1))

  test "minority collusion (2 of 5) cannot move the witnessed median", %{honest: h, collude: c} do
    nodes =
      %{
        "w1" => witness("w1", [h]),
        "w2" => witness("w2", [h]),
        "w3" => witness("w3", [h]),
        "w4" => witness("w4", [h, c]),
        "w5" => witness("w5", [h, c])
      }

    assert_in_delta V3.witnessed_rank(nodes, ~w(w1 w2 w3 w4 w5), "P"), 51.5, 1.0e-9
  end

  test "majority collusion (3 of 5) does move it — the stated limit", %{honest: h, collude: c} do
    nodes =
      %{
        "w1" => witness("w1", [h]),
        "w2" => witness("w2", [h]),
        "w3" => witness("w3", [h, c]),
        "w4" => witness("w4", [h, c]),
        "w5" => witness("w5", [h, c])
      }

    # honest 51.5 holders are now the minority → median is the colluded value
    assert V3.witnessed_rank(nodes, ~w(w1 w2 w3 w4 w5), "P") == 100.0
  end

  test "byzantine relay: mangling in transit is dropped, integrity preserved", %{honest: h} do
    # honest relay: re-frame unchanged → delivered & verifiable
    {:ok, clean, ""} = h |> Wire.encode() |> Wire.decode()
    good = V3.new_node("d", ["P"]) |> V3.ingest_signed(clean)
    assert V3.knows?(good, "P")

    # byzantine relay: tamper the decoded att, re-frame (digest valid), forward
    {:ok, got, ""} = h |> Wire.encode() |> Wire.decode()
    {:ok, mangled, ""} = %{got | delta: 9.9} |> Wire.encode() |> Wire.decode()
    refute Identity.verified?(mangled)
    bad = V3.new_node("d2", ["P"]) |> V3.ingest_signed(mangled)
    refute V3.knows?(bad, "P")
    assert V3.witnessed_rank(%{"d2" => bad}, ["d2"], "P") == 50.0
  end

  test "partition then heal: the cut-off cluster converges via one bridge", %{honest: h} do
    # cluster A sees it; cluster B is partitioned (sees nothing)
    a1 = witness("a1", [h])
    a2 = witness("a2", [h])
    b1 = V3.new_node("b1", ["P"])
    b2 = V3.new_node("b2", ["P"])

    pre = %{"a1" => a1, "a2" => a2, "b1" => b1, "b2" => b2}
    assert_in_delta V3.witnessed_rank(pre, ~w(a1 a2), "P"), 51.5, 1.0e-9
    assert V3.witnessed_rank(pre, ~w(b1 b2), "P") == 50.0

    # bridge: a1 → b1 → b2, bytes only
    hop = fn att -> {:ok, [g], ""} = att |> Wire.encode() |> Wire.decode_stream(); g end
    [held] = V3.held_attestations(a1, "P")
    b1 = V3.ingest_signed(b1, hop.(held))
    [hb] = V3.held_attestations(b1, "P")
    b2 = V3.ingest_signed(b2, hop.(hb))

    healed = %{"a1" => a1, "a2" => a2, "b1" => b1, "b2" => b2}
    assert_in_delta V3.witnessed_rank(healed, ~w(a1 a2 b1 b2), "P"), 51.5, 1.0e-9
  end
end
