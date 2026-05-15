# Phase 2 functional smoke test. Run: mix run priv/repo/phase2_smoke.exs
import Ecto.Query
alias Fu.{Repo, Queues, Accounts, Matching, Friends, Groups}
alias Fu.Accounts.Player

players = Repo.all(from p in Player, order_by: p.id)
[p1, p2, p3 | _] = players

q = Repo.all(from x in Queues.Queue, where: x.state == "open", order_by: x.scheduled_at) |> hd()
q = Queues.get_queue!(q.id)
IO.puts("Queue #{q.id} #{q.format} @#{q.scheduled_at} state=#{q.state}")

# S30 join
case Queues.join(q, p1) do
  {:ok, m} -> IO.puts("JOIN ok: #{p1.display_name} -> #{m.declared_position}")
  {:error, e} -> IO.puts("JOIN err: #{inspect(e)}")
end

# S31 leave (open period)
IO.puts("LEAVE: #{inspect(Queues.leave(q, p1))}")

# S36 auto-match — needs availability covering the queue time
wd = Date.day_of_week(DateTime.to_date(q.scheduled_at)) |> rem(7)
{:ok, _} =
  Accounts.add_availability(p2, %{
    "kind" => "recurring",
    "weekday" => wd,
    "start_time" => "00:00:00",
    "end_time" => "23:59:00"
  })

sug = Matching.suggest(p2)
IO.puts("MATCH suggest(#{p2.display_name}): #{length(sug)} queues; top field=#{(sug |> List.first() || %{}) |> Map.get(:field, %{}) |> Map.get(:name, "-")}")

# S37/S38 friends
IO.puts("FRIEND request: #{inspect(elem(Friends.request_friend(p1, p2), 0))}")
{:ok, _} = Friends.request_friend(p2, p1)  # reverse -> auto-accept
IO.puts("FRIENDS of #{p1.display_name}: #{Friends.list_friends(p1) |> Enum.map(& &1.display_name) |> inspect()}")
IO.puts("friends?(p1,p2)=#{Friends.friends?(p1, p2)}  invite=#{Friends.invite_link(p1)}")
IO.puts("by_phone: #{Friends.find_by_phone_contacts([p3.phone]) |> Enum.map(& &1.display_name) |> inspect()}")

# S39/S40 groups
{:ok, g} = Groups.create_group(p1)
{:ok, _} = Groups.add_member(g, p2)
{:ok, _} = Groups.add_member(g, p3)
g = Groups.get_by_invite(g.invite_code)
IO.puts("GROUP size=#{Groups.member_count(g)} expect=#{Groups.expected_split(Groups.member_count(g))}")
q2 = Repo.all(from x in Queues.Queue, where: x.state == "open", order_by: [desc: x.scheduled_at]) |> hd() |> then(&Queues.get_queue!(&1.id))
IO.puts("fits_queue?(group, q#{q2.id})=#{Groups.fits_queue?(g, q2)}")
IO.puts("queue_as_group: #{inspect(elem(Groups.queue_as_group(g, q2), 0))}")

# S35 resolver
[rq | _] = Repo.all(from x in Queues.Queue, order_by: x.scheduled_at) |> Enum.map(&Queues.get_queue!(&1.id))
{outcome, _} = Queues.resolve_partial_fill(rq)
IO.puts("RESOLVE queue #{rq.id}: #{outcome}")

IO.puts("\nPHASE 2 SMOKE OK")
