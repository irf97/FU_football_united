defmodule Fu.Mesh.WireTest do
  @moduledoc """
  Wire framing: a signed Object becomes a length-delimited, integrity-checked
  frame, chunked to a BLE MTU and reassembled. Codec ≠ crypto — the frame
  digest catches transit corruption; Identity still verifies authorship.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Fu.Mesh.{Wire, Identity, V3}

  defp signed(match, player, delta) do
    {pub, priv} = Identity.keypair_from_seed(:binary.copy(<<3>>, 32))
    V3.attest(match, player, delta, ["w1", "w2"]) |> Identity.sign_attest(priv, pub)
  end

  test "encode → decode round-trips a signed attestation, signature still verifies" do
    att = signed(7, "keeper", -0.8)
    frame = Wire.encode(att)

    assert {:ok, got, ""} = Wire.decode(frame)
    assert got.match == 7 and got.player == "keeper"
    assert_in_delta got.delta, -0.8, 1.0e-9
    assert got.witnesses == ["w1", "w2"]
    assert Identity.verified?(got)
  end

  test "rejects a bad magic / wrong version" do
    assert {:error, :bad_frame} = Wire.decode(<<0, 0, 2, 1, 0::32>>)
    <<_m::16, rest::binary>> = Wire.encode(signed(1, "p", 1.5))
    assert {:error, :bad_frame} = Wire.decode(<<"ZZ", rest::binary>>)
  end

  test "rejects an oversize length without allocating it" do
    assert {:error, :oversize} = Wire.decode(<<"FU", 2, 1, 9_999_999::32, 0>>)
  end

  test "a truncated frame is :incomplete (caller must buffer more)" do
    frame = Wire.encode(signed(1, "p", 1.5))
    short = binary_part(frame, 0, byte_size(frame) - 5)
    assert {:error, :incomplete} = Wire.decode(short)
  end

  test "a single flipped payload byte is caught by the frame digest" do
    frame = Wire.encode(signed(3, "p", 0.3))
    i = 14
    <<head::binary-size(i), b, tail::binary>> = frame
    corrupt = <<head::binary, Bitwise.bxor(b, 1), tail::binary>>
    assert {:error, :corrupt} = Wire.decode(corrupt)
  end

  test "stream: concatenated frames decode in order with leftover handled" do
    a = Wire.encode(signed(1, "a", 1.5))
    b = Wire.encode(signed(2, "b", 0.3))
    {:ok, [x, y], ""} = Wire.decode_stream(a <> b)
    assert x.player == "a" and y.player == "b"

    {:ok, [z], rest} = Wire.decode_stream(a <> binary_part(b, 0, 3))
    assert z.player == "a"
    assert rest == binary_part(b, 0, 3)
  end

  test "MTU chunking: split to tiny chunks and reassemble byte-identical" do
    frame = Wire.encode(signed(9, "mid", 1.6))
    chunks = Wire.chunks(frame, 16)
    assert Enum.all?(chunks, &(byte_size(&1) <= 16))
    assert IO.iodata_to_binary(chunks) == frame
    assert {:ok, _att, ""} = Wire.decode(IO.iodata_to_binary(chunks))
  end

  property "decode never crashes on hostile/garbage input — only {:ok,_} | {:error,reason}" do
    check all junk <- binary(max_length: 200) do
      case Wire.decode(junk) do
        {:ok, _att, _rest} -> :ok
        {:error, r} -> assert r in [:incomplete, :oversize, :corrupt, :version, :bad_frame]
      end
    end
  end

  property "any prefix of a valid frame decodes to :incomplete/:corrupt, never crashes" do
    {pub, priv} = Identity.keypair_from_seed(:binary.copy(<<4>>, 32))
    full = V3.attest(1, "p", 1.5, ["w1"]) |> Identity.sign_attest(priv, pub) |> Wire.encode()

    check all take <- integer(0..(byte_size(full) - 1)) do
      case Wire.decode(binary_part(full, 0, take)) do
        {:ok, _, _} -> flunk("a strict prefix must not decode as a whole frame")
        {:error, r} -> assert r in [:incomplete, :corrupt, :bad_frame]
      end
    end
  end

  property "any signed attestation survives encode → random-MTU chunking → reassembly → decode" do
    {pub, priv} = Identity.keypair_from_seed(:binary.copy(<<5>>, 32))

    check all match <- integer(0..4_000_000_000),
              player <- string(:alphanumeric, min_length: 1, max_length: 20),
              milli <- integer(-30_000..30_000),
              mtu <- integer(1..64) do
      att = V3.attest(match, player, milli / 1000, []) |> Identity.sign_attest(priv, pub)
      reassembled = att |> Wire.encode() |> Wire.chunks(mtu) |> IO.iodata_to_binary()

      assert {:ok, got, ""} = Wire.decode(reassembled)
      assert got.match == match and got.player == player
      assert Identity.verified?(got)
    end
  end
end
