defmodule Fu.Mesh.Wire do
  @moduledoc """
  Wire framing for signed Objects — the transport boundary, frozen.

  A frame is length-delimited and integrity-checked so a peer can read it
  off a byte stream (BLE/Wi-Fi-Aware) and a corrupt or truncated frame is
  rejected cheaply *before* signature verification. The codec is not
  security — `Fu.Mesh.Identity` verifies authorship; the 4-byte digest only
  catches transit bit-rot.

  Frame (all integers big-endian):

      "FU"      2  magic
      0x02      1  version (== protocol v2)
      type      1  0x01 = signed attestation
      len       4  u32, byte length of payload, MUST be <= #{4096}
      payload  len
      digest    4  first 4 bytes of SHA-256(payload)

  Payload (deterministic serialisation of a *signed* attestation):

      match        4  u32
      delta_milli  4  i32  (= round(delta*1000), same as canonical §4)
      player_len   2  u16
      player    plen  UTF-8
      author_pub  32  Ed25519 public key
      sig         64  Ed25519 signature over canonical(att)
      wit_count    2  u16
      [ wlen 2 | witness wlen ] * wit_count
  """

  @magic "FU"
  @version 2
  @type_att 0x01
  @max 4096

  @doc "Max payload size (bytes)."
  def max_payload, do: @max

  ## --- encode ---

  @doc "Serialise a signed attestation into one frame (binary)."
  def encode(%{author_pub: pub, sig: sig} = att)
      when is_binary(pub) and is_binary(sig) do
    payload = ser(att)
    size = byte_size(payload)
    if size > @max, do: raise(ArgumentError, "object #{size}B exceeds #{@max}B cap")
    digest = :crypto.hash(:sha256, payload) |> binary_part(0, 4)
    <<@magic, @version, @type_att, size::32, payload::binary, digest::binary>>
  end

  defp ser(att) do
    p = att.player
    wit = att.witnesses || []
    wbin = for w <- wit, into: <<>>, do: <<byte_size(w)::16, w::binary>>

    <<att.match::32, round(att.delta * 1000)::signed-32, byte_size(p)::16, p::binary,
      att.author_pub::binary-size(32), att.sig::binary-size(64), length(wit)::16,
      wbin::binary>>
  end

  ## --- decode ---

  @doc """
  Decode one frame. `{:ok, att, leftover}` | `{:error, reason}` where
  reason ∈ `:incomplete` (need more bytes — buffer &amp; retry), `:oversize`,
  `:corrupt`, `:version`, `:bad_frame`.
  """
  def decode(<<@magic, @version, _t, len::32, body::binary>>) do
    cond do
      len > @max ->
        {:error, :oversize}

      byte_size(body) < len + 4 ->
        {:error, :incomplete}

      true ->
        <<payload::binary-size(len), digest::binary-size(4), leftover::binary>> = body

        if binary_part(:crypto.hash(:sha256, payload), 0, 4) == digest do
          {:ok, deser(payload), leftover}
        else
          {:error, :corrupt}
        end
    end
  end

  def decode(<<@magic, v, _::binary>>) when v != @version, do: {:error, :version}
  def decode(<<@magic, _::binary>>), do: {:error, :incomplete}
  def decode(bin) when byte_size(bin) < 2, do: {:error, :incomplete}
  def decode(_), do: {:error, :bad_frame}

  defp deser(payload) do
    <<match::32, dm::signed-32, plen::16, player::binary-size(plen), pub::binary-size(32),
      sig::binary-size(64), wc::16, wbin::binary>> = payload

    %{
      match: match,
      player: player,
      delta: dm / 1000,
      witnesses: parse_w(wbin, wc, []),
      author_pub: pub,
      sig: sig,
      size: byte_size(payload)
    }
  end

  defp parse_w(_bin, 0, acc), do: Enum.reverse(acc)

  defp parse_w(<<l::16, w::binary-size(l), rest::binary>>, n, acc),
    do: parse_w(rest, n - 1, [w | acc])

  ## --- stream ---

  @doc "Consume as many whole frames as present; stop at the first partial."
  def decode_stream(bin), do: ds(bin, [])

  defp ds(bin, acc) do
    case decode(bin) do
      {:ok, att, rest} -> ds(rest, [att | acc])
      {:error, :incomplete} -> {:ok, Enum.reverse(acc), bin}
      {:error, reason} -> {:error, reason}
    end
  end

  ## --- MTU chunking ---

  @doc "Split a frame into <= `mtu`-byte chunks (BLE transport layer)."
  def chunks(bin, mtu) when is_integer(mtu) and mtu > 0, do: do_chunks(bin, mtu, [])

  defp do_chunks(<<>>, _mtu, acc), do: Enum.reverse(acc)

  defp do_chunks(bin, mtu, acc) when byte_size(bin) <= mtu,
    do: Enum.reverse([bin | acc])

  defp do_chunks(bin, mtu, acc) do
    <<c::binary-size(mtu), rest::binary>> = bin
    do_chunks(rest, mtu, [c | acc])
  end
end
