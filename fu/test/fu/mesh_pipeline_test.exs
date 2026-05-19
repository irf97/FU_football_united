defmodule Fu.Mesh.PipelineTest do
  @moduledoc """
  The capstone: two nodes converge on a witnessed rank using ONLY framed
  bytes between them — sign → canonical → Wire.encode → MTU chunk → stream
  reassemble → decode → ingest_signed → relay → witnessed rank. No node
  ever touches another's struct; the only channel is a byte stream.
  """
  use ExUnit.Case, async: true

  alias Fu.Mesh.{Identity, V3, Wire}

  # The only inter-node channel: a chunked, reassembled byte stream.
  defp over_the_wire(att, mtu) do
    bytes = att |> Wire.encode() |> Wire.chunks(mtu) |> IO.iodata_to_binary()
    {:ok, [got], ""} = Wire.decode_stream(bytes)
    got
  end

  test "subject's rank propagates C → W1 → W2 purely as bytes; witnesses agree" do
    {cpub, cpriv} = Identity.keypair_from_seed(:binary.copy(<<8>>, 32))
    att = V3.attest(1, "P", 1.5, ["W1", "W2"]) |> Identity.sign_attest(cpriv, cpub)

    # C ──frame/chunks(11)──▶ W1
    w1 = V3.new_node("W1", ["P"]) |> V3.ingest_signed(over_the_wire(att, 11))
    assert [held] = V3.held_attestations(w1, "P")
    assert Identity.verified?(held)

    # W1 relays exactly what it holds ──frame/chunks(7)──▶ W2
    w2 = V3.new_node("W2", ["P"]) |> V3.ingest_signed(over_the_wire(held, 7))

    nodes = %{"W1" => w1, "W2" => w2, "P" => V3.new_node("P", [])}
    assert_in_delta V3.witnessed_rank(nodes, ["W1", "W2"], "P"), 51.5, 1.0e-9
  end

  test "a transit-corrupted frame is rejected by the digest — rank does not move" do
    {cpub, cpriv} = Identity.keypair_from_seed(:binary.copy(<<8>>, 32))
    att = V3.attest(1, "P", 1.5, []) |> Identity.sign_attest(cpriv, cpub)
    frame = Wire.encode(att)
    <<h::binary-size(20), b, t::binary>> = frame
    corrupt = <<h::binary, Bitwise.bxor(b, 0xFF), t::binary>>

    assert {:error, :corrupt} = Wire.decode(corrupt)
    # nothing decoded ⇒ nothing ingested ⇒ witnessed rank stays the default
    w1 = V3.new_node("W1", ["P"])
    assert V3.witnessed_rank(%{"W1" => w1}, ["W1"], "P") == 50.0
  end

  test "codec ≠ crypto: a frame that decodes but fails verification is not state" do
    {cpub, cpriv} = Identity.keypair_from_seed(:binary.copy(<<8>>, 32))
    real = V3.attest(1, "P", 0.3, []) |> Identity.sign_attest(cpriv, cpub)
    # tamper the delta AFTER signing, then re-frame (digest will be valid;
    # the Ed25519 signature will not).
    forged = %{real | delta: 99.0}
    {:ok, got, ""} = Wire.decode(Wire.encode(forged))

    refute Identity.verified?(got)
    w1 = V3.new_node("W1", ["P"]) |> V3.ingest_signed(got)
    refute V3.knows?(w1, "P")
    assert V3.witnessed_rank(%{"W1" => w1}, ["W1"], "P") == 50.0
  end
end
