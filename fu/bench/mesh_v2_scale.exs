# Friend-graph + proximity-TTL scale harness (the Scuttlebutt fix).
#
#   mix run bench/mesh_v2_scale.exs
#   N=10000 R=60 mix run bench/mesh_v2_scale.exs
#
# Deterministic. Each player persistently replicates ~F friends (mostly
# same-region, a few cross-region bridges) and transiently caches proximity
# peers on a TTL. State is updated, not appended. The questions:
#   • does per-device storage stay FLAT as history grows? (vs v1's blow-up)
#   • is the per-encounter payload NFC-feasible?
#   • does a player's latest match reach a quorum of their friend-witnesses?
#   • how big is the friendless-bootstrap gap?

alias Fu.Mesh.V2

defmodule MeshV2Scale do
  @play_rate 0.30
  @ambient_rate 0.40
  @friend_sync 2        # friends a player opportunistically syncs with / round
  @match_size 16
  @region_size 200
  @friends_avg 8
  @cross_friend 0.15    # share of friend edges that bridge regions
  @orphan_rate 0.08     # friendless players (the bootstrap gap)

  def run(n, rounds, seed \\ 42) do
    :rand.seed(:exsss, {seed, seed, seed})
    regions = max(div(n, @region_size), 1)
    players = Enum.to_list(1..n)
    region_of = Map.new(players, fn p -> {p, rem(p, regions)} end)
    by_region = Enum.group_by(players, &region_of[&1])

    friends = build_friends(players, region_of, by_region, regions)
    orphans = for {p, f} <- friends, MapSet.size(f) == 0, do: p
    nodes = Map.new(players, fn p -> {p, V2.new_node(p, MapSet.to_list(friends[p]))} end)

    st = %{
      nodes: nodes,
      friends: friends,
      by_region: by_region,
      regions: regions,
      mcount: 0,
      last_match: %{},
      bytes_sum: 0,
      enc: 0,
      bytes_max: 0,
      reservoir: []
    }

    {ms, fin} =
      :timer.tc(fn -> Enum.reduce(1..rounds, st, fn r, s -> day(s, r) end) end)

    report(n, rounds, regions, length(orphans), fin, div(ms, 1000))
  end

  defp build_friends(players, region_of, by_region, regions) do
    pset = MapSet.new(players)

    Map.new(players, fn p ->
      cond do
        :rand.uniform() < @orphan_rate ->
          {p, MapSet.new()}

        true ->
          k = @friends_avg
          same = (by_region[region_of[p]] || []) -- [p]

          fr =
            for _ <- 1..k, reduce: MapSet.new() do
              acc ->
                cand =
                  if :rand.uniform() < @cross_friend,
                    do: Enum.random(MapSet.to_list(pset)),
                    else: pick(same)

                if cand && cand != p, do: MapSet.put(acc, cand), else: acc
            end

          {p, fr}
      end
    end)
  end

  defp day(st, _round) do
    # 1. Matches — co-present flood: everyone present holds facts about all
    #    16 (transient), then compacts.
    st =
      Enum.reduce(0..(st.regions - 1), st, fn reg, st ->
        pool = st.by_region[reg] || []
        nm = trunc(length(pool) * @play_rate / @match_size)

        Enum.reduce(1..max(nm, 0)//1, st, fn _i, st -> play(st, sample(pool, @match_size)) end)
      end)

    # 2. Friend-graph sync (the persistence backbone — "friends share instant").
    st =
      Enum.reduce(Map.keys(st.nodes), st, fn p, st ->
        fr = MapSet.to_list(st.friends[p])

        Enum.reduce(Enum.take(Enum.shuffle(fr), @friend_sync), st, fn q, st ->
          encounter(st, p, q)
        end)
      end)

    # 3. Ambient proximity pings (sparse same-region pairs).
    st =
      Enum.reduce(0..(st.regions - 1), st, fn reg, st ->
        pool = st.by_region[reg] || []

        Enum.reduce(1..max(trunc(length(pool) * @ambient_rate), 0)//1, st, fn _i, st ->
          case {pick(pool), pick(pool)} do
            {a, b} when a != nil and b != nil and a != b -> encounter(st, a, b)
            _ -> st
          end
        end)
      end)

    # 4. Age proximity caches; evict expired non-friends.
    %{st | nodes: Map.new(st.nodes, fn {k, nd} -> {k, V2.tick(nd)} end)}
  end

  defp play(st, group) do
    midbase = st.mcount

    atts =
      group
      |> Enum.with_index()
      |> Enum.map(fn {p, i} ->
        V2.attest(midbase + i, p, Enum.random([1.5, 0.3, -0.8]) + 0.1, group)
      end)

    # Everyone present ingests every attestation (witnessed the match), compacts.
    nodes =
      Enum.reduce(group, st.nodes, fn p, ns ->
        nd = Enum.reduce(atts, ns[p], &V2.ingest(&2, &1)) |> V2.compact()
        Map.put(ns, p, nd)
      end)

    last =
      group
      |> Enum.with_index()
      |> Enum.reduce(st.last_match, fn {p, i}, acc -> Map.put(acc, p, midbase + i) end)

    %{st | nodes: nodes, mcount: midbase + length(group), last_match: last}
  end

  defp encounter(st, a, b) do
    {na, nb, bytes} = V2.reconcile(st.nodes[a], st.nodes[b])
    nodes = st.nodes |> Map.put(a, na) |> Map.put(b, nb)

    %{
      st
      | nodes: nodes,
        bytes_sum: st.bytes_sum + bytes,
        enc: st.enc + 1,
        bytes_max: max(st.bytes_max, bytes),
        reservoir: res(st.reservoir, bytes)
    }
  end

  defp res(r, _) when length(r) >= 5000, do: r
  defp res(r, x), do: [x | r]

  defp report(n, rounds, regions, n_orphan, st, ms) do
    sample = sample(Map.keys(st.nodes), 500)
    sizes = Enum.map(sample, &V2.store_size(st.nodes[&1]))
    bytes = Enum.map(sample, &V2.store_bytes(st.nodes[&1]))

    # Witness coverage: for non-orphans, did the latest match reach a
    # quorum (> half) of the player's friends?
    covered =
      sample
      |> Enum.filter(&(MapSet.size(st.friends[&1]) > 0 and Map.has_key?(st.last_match, &1)))
      |> Enum.map(fn p ->
        m = st.last_match[p]
        fr = MapSet.to_list(st.friends[p])
        hold = Enum.count(fr, &V2.seen_match?(st.nodes[&1], p, m))
        if hold * 2 >= length(fr), do: 1, else: 0
      end)

    # Orphans: anyone (besides self) still holding their latest match?
    orphan_lost =
      st.nodes
      |> Map.keys()
      |> Enum.filter(&(MapSet.size(st.friends[&1]) == 0 and Map.has_key?(st.last_match, &1)))
      |> sample(300)
      |> Enum.count(fn p ->
        m = st.last_match[p]
        not Enum.any?(Map.delete(st.nodes, p), fn {_id, nd} -> V2.seen_match?(nd, p, m) end)
      end)

    rsv = Enum.sort(st.reservoir)
    p95 = if rsv == [], do: 0, else: Enum.at(rsv, min(round(length(rsv) * 0.95), length(rsv) - 1))
    cov_pct = if covered == [], do: 0.0, else: Enum.sum(covered) / length(covered) * 100

    IO.puts("""

    ── v2  N=#{n}  regions=#{regions}  rounds=#{rounds}  matches=#{st.mcount} ──
      sim wall-clock           : #{ms} ms
      per-device store  mean   : #{round(Enum.sum(sizes) / length(sizes))} entries  (#{kb(round(Enum.sum(bytes) / length(bytes)))})
      per-device store  max    : #{Enum.max(sizes)} entries  (#{kb(Enum.max(bytes))})
      payload  avg / p95 / max : #{div(st.bytes_sum, max(st.enc, 1))} / #{p95} / #{st.bytes_max} bytes
      witness coverage         : #{Float.round(cov_pct, 1)}%  (latest match reached a friend-quorum)
      friendless players       : #{n_orphan}  (#{Float.round(n_orphan / n * 100, 1)}%) — data lost for #{orphan_lost} sampled (bootstrap gap)
    """)
  end

  defp sample(l, k) when length(l) <= k, do: l
  defp sample(l, k), do: l |> Enum.shuffle() |> Enum.take(k)
  defp pick([]), do: nil
  defp pick(l), do: Enum.random(l)
  defp kb(b), do: "#{Float.round(b / 1024, 1)} KB"
end

n = String.to_integer(System.get_env("N") || "0")
r = String.to_integer(System.get_env("R") || "60")

if n > 0,
  do: MeshV2Scale.run(n, r),
  else: for(s <- [100, 1_000, 10_000], do: MeshV2Scale.run(s, r))
