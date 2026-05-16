# Queue-chat feature smoke + token mint. Run: mix run priv/repo/qchat_smoke.exs
import Ecto.Query
alias Fu.{Repo, QueueChat}
alias Fu.Accounts.Player
alias Fu.Queues.QueueMembership

p = Repo.all(from x in Player, order_by: x.id, limit: 1) |> hd()

# A queue this player is queued in
qid =
  Repo.one(
    from m in QueueMembership,
      where: m.player_id == ^p.id and m.status == "queued",
      select: m.queue_id,
      limit: 1
  )

IO.puts("player=#{p.display_name} qid=#{qid}")
IO.puts("member_count=#{QueueChat.member_count(qid)} min=#{QueueChat.min_members()} available?=#{QueueChat.available?(qid)}")
IO.puts("member?(p)=#{QueueChat.member?(qid, p.id)}")

# Non-member should be rejected
non_member_qid =
  Repo.one(
    from q in Fu.Queues.Queue,
      left_join: m in QueueMembership,
      on: m.queue_id == q.id and m.player_id == ^p.id and m.status == "queued",
      where: is_nil(m.id),
      select: q.id,
      limit: 1
  )

case QueueChat.post_message(qid, p, "  E2E hello from #{p.display_name}  ") do
  {:ok, msg} -> IO.puts("post OK -> '#{msg.body}' (trimmed, id=#{msg.id})")
  err -> IO.puts("post FAIL #{inspect(err)}")
end

if non_member_qid do
  IO.puts("non-member post -> #{inspect(QueueChat.post_message(non_member_qid, p, "x"))} (expect :not_member or :not_open)")
end

IO.puts("messages now: #{length(QueueChat.list_messages(qid))}")

File.write!(System.tmp_dir!() <> "/tok5.txt", FuWeb.PlayerAuth.login_token(p.id))
File.write!(System.tmp_dir!() <> "/qid5.txt", to_string(qid))
IO.puts("QCHAT SMOKE OK (token+qid written)")
