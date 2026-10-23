defmodule Fu.AccountsOtpConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Fu.{Accounts, Repo}
  alias Fu.Accounts.{OtpCode, Player}

  @moduletag :postgres_concurrency
  defp unboxed(fun), do: Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fun)

  setup do
    phone =
      "+3168#{System.unique_integer([:positive]) |> Integer.to_string() |> String.pad_leading(7, "0")}"

    on_exit(fn ->
      unboxed(fn ->
        Repo.delete_all(from(o in OtpCode, where: o.phone == ^phone))
        Repo.delete_all(from(p in Player, where: p.phone == ^phone))
      end)
    end)

    {:ok, phone: phone}
  end

  defp simultaneously(fun) do
    parent = self()

    tasks =
      for _ <- 1..12 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> unboxed(fun)
          end
        end)
      end

    for _ <- tasks, do: assert_receive({:ready, _}, 10_000)
    Enum.each(tasks, &send(&1.pid, :go))
    Enum.map(tasks, &Task.await(&1, 30_000))
  end

  test "concurrent requests cannot exceed five deliveries per phone", %{phone: phone} do
    results = simultaneously(fn -> Accounts.request_otp(phone) end)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 5
    assert Enum.count(results, &(&1 == {:error, :rate_limited})) == 7

    unboxed(fn ->
      assert Repo.aggregate(from(o in OtpCode, where: o.phone == ^phone), :count) == 5
    end)
  end

  test "only one concurrent verification can consume a code", %{phone: phone} do
    code =
      unboxed(fn ->
        %Player{} |> Player.registration_changeset(%{phone: phone}) |> Repo.insert!()
        {:ok, code} = Accounts.request_otp(phone)
        code
      end)

    results = simultaneously(fn -> Accounts.verify_otp(phone, code) end)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :invalid_code})) == 11
  end

  test "an older code never becomes usable after the latest code is consumed", %{phone: phone} do
    unboxed(fn ->
      {:ok, older} = Accounts.request_otp(phone)
      {:ok, latest} = Accounts.request_otp(phone)
      assert {:ok, _} = Accounts.verify_otp(phone, latest)
      assert {:error, :invalid_code} = Accounts.verify_otp(phone, older)
    end)
  end
end
