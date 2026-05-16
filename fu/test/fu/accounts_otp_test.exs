defmodule Fu.AccountsOtpTest do
  @moduledoc "P0 — phone-OTP replay protection + code validity (spec §2.13 S1)."
  use Fu.DataCase, async: true

  alias Fu.Accounts
  alias Fu.Accounts.OtpCode

  @phone "+31611112222"

  test "request_otp then verify_otp returns a player" do
    {:ok, code} = Accounts.request_otp(@phone)
    assert {:ok, player} = Accounts.verify_otp(@phone, code)
    assert player.phone == @phone
  end

  test "replay protection — a consumed code cannot be reused" do
    {:ok, code} = Accounts.request_otp(@phone)
    assert {:ok, _} = Accounts.verify_otp(@phone, code)
    assert {:error, :invalid_code} = Accounts.verify_otp(@phone, code)
  end

  test "wrong code is rejected" do
    {:ok, _code} = Accounts.request_otp(@phone)
    assert {:error, :invalid_code} = Accounts.verify_otp(@phone, "000000")
  end

  test "expired code is rejected" do
    past =
      DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

    {:ok, _} =
      %OtpCode{}
      |> OtpCode.changeset(%{phone: @phone, code: "123456", expires_at: past})
      |> Repo.insert()

    assert {:error, :invalid_code} = Accounts.verify_otp(@phone, "123456")
  end

  test "verifying an existing player keeps the same player row" do
    {:ok, c1} = Accounts.request_otp(@phone)
    {:ok, p1} = Accounts.verify_otp(@phone, c1)
    {:ok, c2} = Accounts.request_otp(@phone)
    {:ok, p2} = Accounts.verify_otp(@phone, c2)
    assert p1.id == p2.id
  end

  @tag :documents_gap
  test "AUDIT GAP: request_otp has no rate limit (see audit/test-findings.md)" do
    # Documents shipped behaviour, not desired behaviour: unbounded OTP
    # requests all succeed (SMS-bomb / DB-fill vector). Flagged, not fixed.
    for _ <- 1..25, do: assert({:ok, _} = Accounts.request_otp(@phone))
    count = Repo.aggregate(from(o in OtpCode, where: o.phone == ^@phone), :count, :id)
    assert count >= 25
  end
end
