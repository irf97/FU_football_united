# Proximity-gossip scale harness.
#
#   mix run bench/mesh_scale.exs            # 100 / 1k / 10k
#   N=2000 R=80 mix run bench/mesh_scale.exs
#
# Deterministic (seeded). Models a *geographically clustered* swarm: players
# belong to a region and mostly meet their local crowd; matches are dense
# local gossip floods (everyone at the pitch syncs), ambient pings are
# sparse pair encounters, and a small "travel" rate carries logs across
# regions (the only thing that heals partitions). The realism that matters:
# convergence is NOT free — it depends on the bridge rate.

alias Fu.Mesh

defmodule MeshScale do
  @play_rate 0.30      # share of a region playing on a given day
  @ambient_rate 0.50   # ambient proximity pings per player per day
  @travel_rate 0.02    # share of matches that pull a cross-region traveller
  @match_size 16       # 8v8
  @region_size 200

  def run(n, rounds, seed \\ 42) do
    :rand.seed(:exsss, {seed, seed, seed})
    regions = max(div(n, @region_size), 1)

    players = for i <- 1..n, do: i
    region_of = Map.new(players, fn p -> {p, rem(p, regions)} end)
    by_region = Enum.group_by(players, &region_of[&1])

    nodes = Map.new(players, fn p -> {p, Mesh.new_node(p)} end)

    state = %{
      nodes: nodes,
      by_region: by_region,
      regions: regions,
      total: 0,
      oracle: Mesh.new_node(:oracle),
      bytes_sum: 0,
      enc_count: 0,
      bytes_max: 0,
      reservoir: [],
      last_round_bytes: {0, 0},
      conv90: nil,
      conv99: nil
    }

    {ms, final} =
      :timer.tc(fn ->
        Enum.reduce(1..rounds, state, fn r, st -> day(st, r, rounds) end)
      end)

    report(n, rounds, regions, final, div(ms, 1000))
  end

  defp day(st, round, total_rounds) do
    st = %{st | last_round_bytes: {0, 0}}

    # 1. Matches per region (dense local gossip flood among the 16 present).
    st =
      Enum.reduce(0..(st.regions - 1), st, fn reg, st ->
        pool = st.by_region[reg] || []
        n_matches = round_int(length(pool) * @play_rate / @match_size)

        Enum.reduce(1..max(n_matches, 0)//1, st, fn _m, st ->
          group = sample(pool, @match_size)

          group =
            if :rand.uniform() < @travel_rate and map_size(st.nodes) > @match_size do
              # one local seat taken by a traveller from elsewhere (bridge)
              [_ | rest] = group
              [Enum.random(1..map_size(st.nodes)) | rest] |> Enum.uniq()
            else
              group
            end

          play_match(st, group)
        end)
      end)

    # 2. Ambient proximity pings — sparse, same-region pair encounters.
    st =
      Enum.reduce(0..(st.regions - 1), st, fn reg, st ->
        pool = st.by_region[reg] || []
        pings = round_int(length(pool) * @ambient_rate)

        Enum.reduce(1..max(pings, 0)//1, st, fn _i, st ->
          case {pick(pool), pick(pool)} do
            {a, b} when a != nil and b != nil and a != b -> ping(st, a, b)
            _ -> st
          end
        end)
      end)

    maybe_track_convergence(st, round, total_rounds)
  end

  # A match: one content-addressed event, then the 16 present flood-merge
  # (physical co-presence = you can sync with everyone at the pitch).
  defp play_match(st, group) do
    mid = {st.total, hd(group)}
    deltas = Map.new(group, fn p -> {p, Enum.random([1.5, 0.3, -0.8]) + 0.1} end)
    ev = Mesh.match_event(mid, deltas)

    union =
      Enum.reduce(group, %{ev.id => ev}, fn p, acc ->
        Map.merge(acc, st.nodes[p].store)
      end)

    {nodes, recv} =
      Enum.reduce(group, {st.nodes, 0}, fn p, {ns, acc} ->
        had = ns[p].store
        gained = Map.drop(union, Map.keys(had))
        bytes = gained |> Map.values() |> Enum.reduce(0, &(&1.size + &2))
        {Map.put(ns, p, %{ns[p] | store: union}), acc + bytes}
      end)

    st
    |> Map.put(:nodes, nodes)
    |> Map.update!(:oracle, &Mesh.append(&1, ev))
    |> Map.update!(:total, &(&1 + 1))
    |> record(recv, length(group))
  end

  defp ping(st, a, b) do
    {na, nb, bytes} = Mesh.reconcile(st.nodes[a], st.nodes[b])
    st
    |> Map.update!(:nodes, &(&1 |> Map.put(a, na) |> Map.put(b, nb)))
    |> record(bytes, 1)
  end

  defp record(st, bytes, _grp) do
    {lr_b, lr_c} = st.last_round_bytes

    %{
      st
      | bytes_sum: st.bytes_sum + bytes,
        enc_count: st.enc_count + 1,
        bytes_max: max(st.bytes_max, bytes),
        reservoir: reservoir(st.reservoir, bytes),
        last_round_bytes: {lr_b + bytes, lr_c + 1}
    }
  end

  defp reservoir(r, _x) when length(r) >= 4000, do: r
  defp reservoir(r, x), do: [x | r]

  defp maybe_track_convergence(st, round, total_rounds) do
    if rem(round, 5) == 0 or round == total_rounds do
      cov = coverage(st)
      st = if st.conv90 == nil and cov >= 0.90, do: %{st | conv90: round}, else: st
      st = if st.conv99 == nil and cov >= 0.99, do: %{st | conv99: round}, else: st
      Map.put(st, :last_cov, cov)
    else
      st
    end
  end

  defp coverage(%{total: 0}), do: 1.0

  defp coverage(st) do
    sample = sample(Map.keys(st.nodes), 400)
    Enum.reduce(sample, 0.0, fn p, acc -> acc + Mesh.log_count(st.nodes[p]) / st.total end) /
      length(sample)
  end

  defp report(n, rounds, regions, st, ms) do
    sample = sample(Map.keys(st.nodes), 400)

    log_counts = Enum.map(sample, &Mesh.log_count(st.nodes[&1]))
    log_bytes = Enum.map(sample, &Mesh.log_bytes(st.nodes[&1]))

    players = sample(Map.keys(st.nodes), 60)

    rank_err =
      for p <- players, q <- Enum.take(sample, 80) do
        abs(Mesh.rank(st.nodes[q], p) - Mesh.rank(st.oracle, p))
      end

    {lr_b, lr_c} = st.last_round_bytes
    res = Enum.sort(st.reservoir)
    p95 = if res == [], do: 0, else: Enum.at(res, min(round(length(res) * 0.95), length(res) - 1))

    IO.puts("""

    ── N=#{n}  regions=#{regions}  rounds=#{rounds}  events=#{st.total} ──
      sim wall-clock        : #{ms} ms
      convergence (final)   : #{pct(st[:last_cov] || coverage(st))}
      rounds → 90% / 99%    : #{st.conv90 || "—"} / #{st.conv99 || "—"}
      encounters total      : #{st.enc_count}
      payload  avg / p95 / max (bytes): #{div(st.bytes_sum, max(st.enc_count, 1))} / #{p95} / #{st.bytes_max}
      steady-state payload  : #{if lr_c > 0, do: div(lr_b, lr_c), else: 0} B/encounter (final round)
      per-device log  max   : #{Enum.max(log_counts)} events  (#{kb(Enum.max(log_bytes))})
      per-device log  mean  : #{round(Enum.sum(log_counts) / length(log_counts))} events  (#{kb(round(Enum.sum(log_bytes) / length(log_bytes)))})
      rank err vs oracle    : mean #{f(mean(rank_err))}  p95 #{f(pctl(rank_err, 0.95))}  max #{f(Enum.max(rank_err))}
    """)
  end

  # helpers
  defp round_int(x), do: trunc(Float.round(x * 1.0))
  defp sample(list, k) when length(list) <= k, do: list
  defp sample(list, k), do: list |> Enum.shuffle() |> Enum.take(k)
  defp pick([]), do: nil
  defp pick(list), do: Enum.random(list)
  defp mean([]), do: 0.0
  defp mean(xs), do: Enum.sum(xs) / length(xs)

  defp pctl([], _), do: 0.0

  defp pctl(xs, q) do
    s = Enum.sort(xs)
    Enum.at(s, min(round(length(s) * q), length(s) - 1))
  end

  defp pct(x), do: "#{Float.round(x * 100, 2)}%"
  defp f(x), do: Float.round(x * 1.0, 3)
  defp kb(b), do: "#{Float.round(b / 1024, 1)} KB"
end

n = String.to_integer(System.get_env("N") || "0")
r = String.to_integer(System.get_env("R") || "60")

if n > 0 do
  MeshScale.run(n, r)
else
  for size <- [100, 1_000, 10_000], do: MeshScale.run(size, r)
end
