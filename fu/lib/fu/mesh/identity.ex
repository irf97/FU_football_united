defmodule Fu.Mesh.Identity do
  @moduledoc """
  Protocol-grade identity for the mesh model — real Ed25519, not an
  abstraction. A persona/device is a keypair; an attestation is only
  *state* if its signature verifies against its declared author key.

  This turns the simulation into a faithful protocol reference: the Rust
  runtime must reproduce exactly this — sign on assert, verify on receive,
  drop the unverifiable, never relay it.
  """

  @doc "A fresh random Ed25519 keypair `{public, private}`."
  def keypair, do: :crypto.generate_key(:eddsa, :ed25519)

  @doc """
  Deterministic Ed25519 keypair from a 32-byte seed. Same seed ⇒ same
  identity — the basis for persona recovery (node L6) and for reproducible
  conformance vectors (Ed25519 signing is itself deterministic, RFC 8032).
  """
  def keypair_from_seed(seed) when is_binary(seed) and byte_size(seed) == 32,
    do: :crypto.generate_key(:eddsa, :ed25519, seed)

  @doc "Detached Ed25519 signature over `payload` (a binary)."
  def sign(priv, payload) when is_binary(payload),
    do: :crypto.sign(:eddsa, :none, payload, [priv, :ed25519])

  @doc "Verify `sig` over `payload` against `pub`."
  def verify(pub, payload, sig) when is_binary(payload) do
    :crypto.verify(:eddsa, :none, payload, sig, [pub, :ed25519])
  rescue
    _ -> false
  end

  @doc "Stable short content-addressed id of a public key (its address)."
  def address(pub) do
    :crypto.hash(:sha256, pub) |> Base.encode16(case: :lower) |> binary_part(0, 16)
  end

  # Canonical, signature-stable encoding of the *meaningful* fields only.
  # Excludes sig/author_pub/size so tampering any of match/player/delta
  # invalidates the signature.
  defp canonical(%{match: m, player: p, delta: d}), do: "#{m}|#{p}|#{d}"

  @doc "Attach an Ed25519 signature + author key to an attestation."
  def sign_attest(att, priv, pub) do
    Map.merge(att, %{sig: sign(priv, canonical(att)), author_pub: pub})
  end

  @doc "Is this a validly signed attestation (author key actually signed it)?"
  def verified?(%{sig: sig, author_pub: pub} = att)
      when is_binary(sig) and is_binary(pub),
      do: verify(pub, canonical(att), sig)

  def verified?(_), do: false
end
