# v3 scale harness — subject-directed relay + instant friend-share +
# proximity-over-time acquaintances. Does routing fix v2's witness-coverage
# collapse while keeping storage flat and payload NFC-sized?
#
#   mix run --no-start bench/mesh_v3_scale.exs
#   N=10000 R=60 mix run --no-start bench/mesh_v3_scale.exs

alias Fu.Mesh.V3

defmodule MeshV3Scale do
  @play_rate 0.30
  @ambient_rate 0.40
  @friend_sync 2
  @match_size 16
  @region_size 200
  @friends_avg 8
  @cross_friend 0.15
  @orphan_rate 0.08

  def run(n, rounds, seed \\ 42) do
    :rand.seed(:exsss, {seed, seed, seed})
    regions = max(div(n, @region_size), 1)
    players = Enum.to_list(1..n)
    region_of = Map.new(players, fn p -> {p, rem(p, regions)} end)
    by_region = Enum.group_by(players, &region_of[&1])
    friends = build_friends(players, region_of, by_region)
    orphans = for {p, f} <- friends, MapSet.size(f) == 0, do: p
    wl = Map.new(friends, fn {p, f} -> {p, MapSet.to_list(f)} end)
    nodes = Map.new(players, fn p -> {p, V3.new_node(p, wl[p])} end)

    st = %{
      nodes: nodes,
      friends: friends,
      wl: wl,
      by_region: by_region,
      regions: regions,
      mcount: 0,
      last_match: %{},
      bytes_sum: 0,
      enc: 0,
      bytes_max: 0,
      reservoir: []
    }

    {ms, fin} = :timer.tc(fn -> Enum.reduce(1..rounds, st, fn r, s -> day(s, r) end) end)
    report(n, rounds, regions, length(orphans), fin, div(ms, 1000))
  end

  defp build_friends(players, region_of, by_region) do
    pset = MapSet.new(players)

    Map.new(players, fn p ->
      if :rand.uniform() < @orphan_rate do
        {p, MapSet.new()}
      else
        same = (by_region[region_of[p]] || []) -- [p]

        fr =
          for _ <- 1..@friends_avg, reduce: MapSet.new() do
            acc ->
              c =
                if :rand.uniform() < @cross_friend,
                  do: Enum.random(MapSet.to_list(pset)),
                  else: pick(same)

              if c && c != p, do: MapSet.put(acc, c), else: acc
          end

        {p, fr}
      end
    end)
  end

  defp day(st, _r) do
    st =
      Enum.reduce(0..(st.regions - 1), st, fn reg, st ->
        pool = st.by_region[reg] || []
        nm = trunc(length(pool) * @play_rate / @match_size)
        Enum.reduce(1..max(nm, 0)//1, st, fn _i, st -> play(st, sample(pool, @match_size)) end)
      end)

    # friend-graph sync (instant friend-share backbone)
    st =
      Enum.reduce(Map.keys(st.nodes), st, fn p, st ->
        Enum.reduce(Enum.take(Enum.shuffle(MapSet.to_list(st.friends[p])), @friend_sync), st, fn q, st ->
          encounter(st, p, q)
        end)
      end)

    # ambient proximity (also accrues acquaintance)
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

    %{st | nodes: Map.new(st.nodes, fn {k, nd} -> {k, V3.tick(nd)} end)}
  end

  defp play(st, group) do
    base = st.mcount

    atts =
      group
      |> Enum.with_index()
      |> Enum.map(fn {p, i} ->
        V3.attest(base + i, p, Enum.random([1.5, 0.3, -0.8]) + 0.1, st.wl[p] || [])
      end)

    # Everyone present ingests all facts (witnessed the match) + accrues
    # proximity with a few co-participants, then compacts.
    nodes =
      Enum.reduce(group, st.nodes, fn p, ns ->
        nd =
          atts
          |> Enum.reduce(ns[p], &V3.ingest(&2, &1))

        nd =
          group
          |> Enum.reject(&(&1 == p))
          |> Enum.take(4)
          |> Enum.reduce(nd, fn q, acc -> V3.met(acc, q) end)
          |> V3.compact()

        Map.put(ns, p, nd)
      end)

    last =
      group
      |> Enum.with_index()
      |> Enum.reduce(st.last_match, fn {p, i}, acc -> Map.put(acc, p, base + i) end)

    %{st | nodes: nodes, mcount: base + length(group), last_match: last}
  end

  defp encounter(st, a, b) do
    na0 = V3.met(st.nodes[a], b)
    nb0 = V3.met(st.nodes[b], a)
    {na, nb, bytes} = V3.reconcile(na0, nb0)
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
    sizes = Enum.map(sample, &V3.store_size(st.nodes[&1]))
    bytes = Enum.map(sample, &V3.store_bytes(st.nodes[&1]))
    acqs = Enum.map(sample, fn p -> Enum.count(st.nodes[p].prox, fn {q, _} -> V3.acquaintance?(st.nodes[p], q) end) end)

    targets =
      Enum.filter(sample, &(MapSet.size(st.friends[&1]) > 0 and Map.has_key?(st.last_match, &1)))

    cov = fn quorum_fn ->
      hits =
        Enum.count(targets, fn p ->
          m = st.last_match[p]
          fr = MapSet.to_list(st.friends[p])
          hold = Enum.count(fr, &V3.seen_match?(st.nodes[&1], p, m))
          quorum_fn.(hold, length(fr))
        end)

      if targets == [], do: 0.0, else: hits / length(targets) * 100
    end

    maj = cov.(fn hold, f -> hold * 2 >= f end)
    q2 = cov.(fn hold, _ -> hold >= 2 end)

    # Friendless-bootstrap fix: of orphans, what fraction have their latest
    # match held by ≥2 PROVISIONAL witnesses (sustained acquaintances)?
    orphan_ids =
      st.nodes
      |> Map.keys()
      |> Enum.filter(
        &(MapSet.size(Map.get(st.friends, &1, MapSet.new())) == 0 and
            Map.has_key?(st.last_match, &1))
      )
      |> sample(200)

    orphan_cov =
      if orphan_ids == [] do
        0.0
      else
        hits =
          Enum.count(orphan_ids, fn p ->
            m = st.last_match[p]

            held =
              Enum.count(st.nodes, fn {id, node} ->
                id != p and V3.acquaintance?(node, p) and V3.seen_match?(node, p, m)
              end)

            held >= 2
          end)

        hits / length(orphan_ids) * 100
      end

    rsv = Enum.sort(st.reservoir)
    p95 = if rsv == [], do: 0, else: Enum.at(rsv, min(round(length(rsv) * 0.95), length(rsv) - 1))

    IO.puts("""

    ── v3  N=#{n}  regions=#{regions}  rounds=#{rounds}  matches=#{st.mcount} ──
      sim wall-clock           : #{ms} ms
      per-device store mean/max: #{round(Enum.sum(sizes) / length(sizes))} / #{Enum.max(sizes)} entries  (#{kb(round(Enum.sum(bytes) / length(bytes)))} / #{kb(Enum.max(bytes))})
      payload  avg / p95 / max : #{div(st.bytes_sum, max(st.enc, 1))} / #{p95} / #{st.bytes_max} bytes
      witness coverage  major. : #{Float.round(maj, 1)}%
      witness coverage  ≥2     : #{Float.round(q2, 1)}%
      acquaintances / node     : #{Float.round(Enum.sum(acqs) / length(acqs), 1)} avg
      friendless players       : #{n_orphan}  (#{Float.round(n_orphan / n * 100, 1)}%)
      orphan recoverable (≥2 prov. witnesses): #{Float.round(orphan_cov, 1)}%
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
if n > 0, do: MeshV3Scale.run(n, r), else: for(s <- [100, 1_000, 10_000], do: MeshV3Scale.run(s, r))
