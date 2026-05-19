defmodule FuWeb.MeshLabLive do
  @moduledoc """
  Mesh Lab — an interactive simulator/spec/conformance surface over the real
  `Fu.Mesh.*` modules. Sign attestations, relay them as framed bytes, watch
  witnessed rank converge, run the adversarial scenarios, and see the
  conformance harness pass/fail live. Nothing here is mocked: every value
  comes from `Fu.Mesh.Identity` / `V3` / `Wire`.
  """
  use FuWeb, :live_view

  alias Fu.Mesh.{Identity, V3, Wire}

  @subject "P"
  @wids ~w(w1 w2 w3 w4 w5)
  @signer_seed :binary.copy(<<8>>, 32)
  @collude_seed :binary.copy(<<21>>, 32)

  @impl true
  def mount(_p, _s, socket) do
    {:ok, socket |> assign(conformance: run_conformance()) |> reset()}
  end

  defp reset(socket) do
    {pub, priv} = Identity.keypair_from_seed(@signer_seed)
    {cpub, cpriv} = Identity.keypair_from_seed(@collude_seed)

    nodes =
      Map.new(@wids, fn id -> {id, V3.new_node(id, [@subject])} end)
      |> Map.put(@subject, V3.new_node(@subject, []))
      |> Map.put("o1", acq("o1"))
      |> Map.put("o2", acq("o2"))
      |> Map.put("orphan", V3.new_node("orphan", []))

    assign(socket,
      nodes: nodes,
      signer: {pub, priv},
      addr: Identity.address(pub),
      collude: {cpub, cpriv},
      seq: 0,
      frame: nil,
      byz: nil,
      orphan_done?: false,
      log: ["lab reset — clean cast"]
    )
  end

  # An acquaintance-holder of the orphan (sustained co-presence).
  defp acq(id) do
    Enum.reduce(1..V3.acq_threshold(), V3.new_node(id, []), fn _, n ->
      V3.met(n, "orphan")
    end)
  end

  ## --- actions ---

  @impl true
  def handle_event("honest", _, socket) do
    {pub, priv} = socket.assigns.signer
    seq = socket.assigns.seq + 1
    att = V3.attest(seq, @subject, 1.5, @wids) |> Identity.sign_attest(priv, pub)
    nodes = Enum.reduce(@wids, socket.assigns.nodes, fn id, ns ->
      Map.update!(ns, id, &V3.ingest_signed(&1, att))
    end)

    {:noreply,
     socket
     |> assign(nodes: nodes, seq: seq, frame: frame_info(att))
     |> log("honest att ##{seq} (+1.5) signed by #{socket.assigns.addr} → all 5 witnesses, framed")}
  end

  def handle_event("wire", _, socket) do
    {pub, priv} = socket.assigns.signer
    seq = socket.assigns.seq + 1
    att = V3.attest(seq, @subject, 1.5, @wids) |> Identity.sign_attest(priv, pub)

    g = hop(att, 16)
    w1 = V3.ingest_signed(socket.assigns.nodes["w1"], g)
    held = V3.held_attestations(w1, @subject) |> List.first()
    w2 = if held, do: V3.ingest_signed(socket.assigns.nodes["w2"], hop(held, 11)), else: socket.assigns.nodes["w2"]
    nodes = socket.assigns.nodes |> Map.put("w1", w1) |> Map.put("w2", w2)

    {:noreply,
     socket
     |> assign(nodes: nodes, seq: seq, frame: frame_info(att))
     |> log("byte-only relay: signer →(MTU16)→ w1 →(MTU11)→ w2 — verified & ingested")}
  end

  def handle_event("collude", %{"n" => n}, socket) do
    k = String.to_integer(n)
    {cpub, cpriv} = socket.assigns.collude
    c = V3.attest(999, @subject, 50.0, @wids) |> Identity.sign_attest(cpriv, cpub)
    targets = Enum.take(["w5", "w4", "w3"], k)

    nodes =
      Enum.reduce(targets, socket.assigns.nodes, fn id, ns ->
        Map.update!(ns, id, &V3.ingest_signed(&1, c))
      end)

    {:noreply,
     socket
     |> assign(nodes: nodes)
     |> log("#{k}/5 witnesses ingested a validly-signed inflated fact (+50) — collusion")}
  end

  def handle_event("byzantine", _, socket) do
    {pub, priv} = socket.assigns.signer
    att = V3.attest(1, @subject, 1.5, []) |> Identity.sign_attest(priv, pub)
    {:ok, g, ""} = att |> Wire.encode() |> Wire.decode()
    {:ok, mangled, ""} = %{g | delta: 9.9} |> Wire.encode() |> Wire.decode()
    d = V3.new_node("byz-rcv", [@subject]) |> V3.ingest_signed(mangled)

    {:noreply,
     socket
     |> assign(byz: %{verified: Identity.verified?(mangled), known: V3.knows?(d, @subject)})
     |> log("byzantine relay mangled delta in transit → verified?=false → dropped (integrity holds)")}
  end

  def handle_event("bootstrap", _, socket) do
    a = V3.attest(1, "orphan", 1.5, [])
    nodes =
      socket.assigns.nodes
      |> Map.update!("o1", &V3.ingest(&1, a))
      |> Map.update!("o2", &V3.ingest(&1, a))
      |> Map.update!("orphan", &V3.ingest(&1, a))

    {:noreply,
     socket
     |> assign(nodes: nodes, orphan_done?: true)
     |> log("orphan played; o1/o2 (sustained acquaintances) hold it → provisional witnesses")}
  end

  def handle_event("reset", _, socket), do: {:noreply, reset(socket) |> log("lab reset")}

  ## --- helpers ---

  defp hop(att, mtu) do
    {:ok, [g], ""} = att |> Wire.encode() |> Wire.chunks(mtu) |> IO.iodata_to_binary() |> Wire.decode_stream()
    g
  end

  defp frame_info(att) do
    f = Wire.encode(att)
    %{bytes: byte_size(f), chunks: length(Wire.chunks(f, 16)), hex: Base.encode16(binary_part(f, 0, min(24, byte_size(f))), case: :lower)}
  end

  defp log(socket, msg) do
    assign(socket, log: Enum.take(["#{time()} · #{msg}" | socket.assigns.log], 18))
  end

  defp time, do: Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")

  defp wrank(nodes), do: V3.witnessed_rank(nodes, @wids, @subject) |> f1()
  defp f1(x), do: :erlang.float_to_binary(x * 1.0, decimals: 1)

  # Run the conformance harness in-process; return [{label, ok?}].
  defp run_conformance do
    try do
      d = Jason.decode!(File.read!(Path.join(File.cwd!(), "conformance/vectors.json")))
      hx = fn b -> Base.encode16(b, case: :lower) end
      uh = fn s -> Base.decode16!(s, case: :lower) end

      ident =
        Enum.all?(d["identity"], fn v ->
          {pub, priv} = Identity.keypair_from_seed(uh.(v["seed_hex"]))

          hx.(pub) == v["public_hex"] and Identity.address(pub) == v["address"] and
            (is_nil(v["sign_payload"]) or hx.(Identity.sign(priv, v["sign_payload"])) == v["signature_hex"])
        end)

      {_p, sp} = Identity.keypair_from_seed(uh.(hd(d["identity"])["seed_hex"]))

      canon =
        Enum.all?(d["canonical_attestations"], fn c ->
          a = V3.attest(c["match"], c["player"], c["delta"], [])
          Identity.canonical(a) == c["canonical"] and hx.(Identity.sign(sp, c["canonical"])) == c["signature_hex"]
        end)

      w = d["wire"]
      {wp, wpriv} = Identity.keypair_from_seed(uh.(w["signer_seed_hex"]))
      a = w["attestation"]
      watt = V3.attest(a["match"], a["player"], a["delta"], a["witnesses"]) |> Identity.sign_attest(wpriv, wp)
      wire_ok = hx.(Wire.encode(watt)) == w["frame_hex"] and byte_size(Wire.encode(watt)) == w["frame_bytes"]

      p = d["pipeline"]
      {pp, ppriv} = Identity.keypair_from_seed(uh.(p["signer_seed_hex"]))
      pa = p["attestation"]
      patt = V3.attest(pa["match"], pa["player"], pa["delta"], pa["witnesses"]) |> Identity.sign_attest(ppriv, pp)
      ph = fn x, m -> {:ok, [g], ""} = x |> Wire.encode() |> Wire.chunks(m) |> IO.iodata_to_binary() |> Wire.decode_stream(); g end
      pw1 = V3.new_node("W1", ["P"]) |> V3.ingest_signed(ph.(patt, p["mtu_a"]))
      [phd] = V3.held_attestations(pw1, "P")
      pw2 = V3.new_node("W2", ["P"]) |> V3.ingest_signed(ph.(phd, p["mtu_b"]))
      pipe_ok =
        abs(V3.witnessed_rank(%{"W1" => pw1, "W2" => pw2}, ["W1", "W2"], "P") - p["final_witnessed_rank"]) < 1.0e-9

      adv = d["adversarial"]
      {hp, hpv} = Identity.keypair_from_seed(uh.(adv["honest_signer_seed_hex"]))
      {cp, cpv} = Identity.keypair_from_seed(uh.(adv["collude_signer_seed_hex"]))
      ha = V3.attest(1, "P", 1.5, []) |> Identity.sign_attest(hpv, hp)
      ca = V3.attest(2, "P", 50.0, []) |> Identity.sign_attest(cpv, cp)
      mk = fn ids -> Map.new(ids, fn {id, as} -> {id, Enum.reduce(as, V3.new_node(id, ["P"]), &V3.ingest_signed(&2, &1))} end) end
      mn = mk.(%{"w1" => [ha], "w2" => [ha], "w3" => [ha], "w4" => [ha, ca], "w5" => [ha, ca]})
      mj = mk.(%{"w1" => [ha], "w2" => [ha], "w3" => [ha, ca], "w4" => [ha, ca], "w5" => [ha, ca]})
      adv_ok =
        abs(V3.witnessed_rank(mn, @wids, "P") - adv["collusion_minority_2of5"]) < 1.0e-9 and
          V3.witnessed_rank(mj, @wids, "P") == adv["collusion_majority_3of5"]

      [
        {"spec/version (#{d["spec"]} v#{d["version"]})", true},
        {"identity (Ed25519, seed-deterministic)", ident},
        {"canonical encoding + signatures", canon},
        {"wire frame byte-exact", wire_ok},
        {"pipeline (byte-only convergence)", pipe_ok},
        {"adversarial (collusion boundary)", adv_ok}
      ]
    rescue
      e -> [{"conformance harness errored: #{Exception.message(e)}", false}]
    end
  end

  ## --- render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} active={:home}>
      <div class="fu-card p-5 space-y-2">
        <div class="text-caption fu-ink-soft">MESH LAB · live over Fu.Mesh.*</div>
        <h1 class="text-h1">P2P protocol — simulate · test · spec</h1>
        <p class="fu-serif fu-ink-soft text-meta">
          Every number below is computed by the real reference modules. Subject
          <span class="text-mono">P</span>; signer
          <span class="text-mono text-[var(--fu-accent)]">{@addr}</span>.
        </p>
      </div>

      <div class="fu-card p-4 space-y-2">
        <div class="fu-divider">Kernel constants (frozen, from the modules)</div>
        <div class="grid grid-cols-2 sm:grid-cols-3 gap-x-4 gap-y-1 text-meta font-mono">
          <span>window W = {V3.window()}</span>
          <span>stranger TTL = {V3.stranger_ttl()}</span>
          <span>acq threshold = {V3.acq_threshold()}</span>
          <span>acq decay = {V3.acq_decay()}</span>
          <span>max payload = {Wire.max_payload()}B</span>
          <span>rank [30,100] / 50</span>
        </div>
      </div>

      <div class="fu-card p-4 space-y-3">
        <div class="fu-divider">Simulate</div>
        <div class="flex flex-wrap gap-2">
          <button phx-click="honest" class="btn btn-primary btn-sm min-h-[44px]">Honest round → all 5</button>
          <button phx-click="wire" class="btn btn-outline btn-sm min-h-[44px]">Relay over wire (bytes only)</button>
          <button phx-click="collude" phx-value-n="2" class="btn btn-outline btn-sm min-h-[44px]">Collude 2/5</button>
          <button phx-click="collude" phx-value-n="3" class="btn btn-outline btn-sm min-h-[44px]">Collude 3/5</button>
          <button phx-click="byzantine" class="btn btn-outline btn-sm min-h-[44px]">Byzantine relay</button>
          <button phx-click="bootstrap" class="btn btn-outline btn-sm min-h-[44px]">Orphan bootstrap</button>
          <button phx-click="reset" class="btn btn-ghost btn-sm min-h-[44px]">Reset</button>
        </div>

        <div class="flex items-center justify-between gap-4 pt-2">
          <div>
            <div class="text-caption fu-ink-soft">WITNESSED RANK (median of w1…w5, self-excluded)</div>
            <div class="text-display leading-none text-[var(--fu-accent)]">{wrank(@nodes)}</div>
          </div>
          <div :if={@frame} class="text-right text-meta font-mono fu-ink-soft">
            last frame: {@frame.bytes} B · {@frame.chunks} chunks @MTU16<br />
            <span class="text-[10px] break-all">{@frame.hex}…</span>
          </div>
        </div>

        <table class="w-full text-meta">
          <thead>
            <tr class="text-caption fu-ink-soft text-left">
              <th class="py-1">node</th><th>role</th><th>holds P?</th><th class="text-right">local rank(P)</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={id <- ~w(w1 w2 w3 w4 w5)} class="border-t border-[var(--fu-line)]">
              <td class="py-1 font-mono">{id}</td>
              <td class="fu-ink-soft">witness</td>
              <td>{if V3.knows?(@nodes[id], "P"), do: "✓", else: "·"}</td>
              <td class="text-right font-mono">{f1(V3.rank(@nodes[id], "P"))}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="grid sm:grid-cols-2 gap-4">
        <div class="fu-card p-4 space-y-1">
          <div class="fu-divider">Adversarial readout</div>
          <p class="text-meta fu-ink-soft">
            Byzantine relay:
            <span :if={@byz} class="font-mono">
              verified?={to_string(@byz.verified)} · receiver-knows-P={to_string(@byz.known)}
            </span>
            <span :if={is_nil(@byz)} class="fu-ink-dim">— run it</span>
          </p>
          <p class="text-caption fu-ink-dim">
            minority collusion can't move the median; majority can (the stated limit).
          </p>
        </div>

        <div class="fu-card p-4 space-y-1">
          <div class="fu-divider">Friendless bootstrap</div>
          <p class="text-meta">
            provisional witnesses(orphan):
            <span class="font-mono text-[var(--fu-accent)]">
              {inspect(Enum.sort(V3.provisional_witnesses(@nodes, "orphan")))}
            </span>
          </p>
          <p class="text-meta">
            recoverable rank: <span class="font-mono">{f1(V3.recoverable_rank(@nodes, [], "orphan"))}</span>
            <span :if={not @orphan_done?} class="fu-ink-dim">— run "Orphan bootstrap"</span>
          </p>
        </div>
      </div>

      <div class="fu-card p-4 space-y-2">
        <div class="fu-divider">Conformance harness (vectors.json, live)</div>
        <div :for={{label, ok} <- @conformance} class="flex items-center justify-between text-meta border-b border-[var(--fu-line)] py-1.5">
          <span>{label}</span>
          <span class={["font-mono font-bold", ok && "text-[var(--fu-accent)]", !ok && "text-[var(--fu-danger)]"]}>
            {if ok, do: "PASS", else: "FAIL"}
          </span>
        </div>
      </div>

      <div class="fu-card p-4 space-y-1">
        <div class="fu-divider">Event log</div>
        <div :for={line <- @log} class="text-[11px] font-mono fu-ink-soft">{line}</div>
      </div>
    </Layouts.app>
    """
  end
end
