defmodule Fu.AccountsOtpHardeningTest do
  @moduledoc "AUDIT #1 — OTP abuse resistance (rate limit + verify attempt cap)."
  use Fu.DataCase, async: true

  alias Fu.Accounts

  @phone "+31699998888"

  describe "request_otp/1 rate limiting" do
    test "blocks once the per-phone request cap in the window is hit" do
      for _ <- 1..5, do: assert({:ok, _} = Accounts.request_otp(@phone))
      assert {:error, :rate_limited} = Accounts.request_otp(@phone)
    end

    test "the cap is per-phone — another number is unaffected" do
      for _ <- 1..5, do: Accounts.request_otp(@phone)
      assert {:ok, _} = Accounts.request_otp("+31611110000")
    end
  end

  describe "verify_otp/2 attempt cap" do
    test "burns the active code after too many wrong guesses (no brute force)" do
      {:ok, code} = Accounts.request_otp(@phone)
      for _ <- 1..5, do: assert({:error, _} = Accounts.verify_otp(@phone, "000000"))

      # The code is now spent — even the *correct* value is rejected.
      assert {:error, reason} = Accounts.verify_otp(@phone, code)
      assert reason in [:locked, :invalid_code]
    end

    test "a correct code within the attempt budget still works" do
      {:ok, code} = Accounts.request_otp(@phone)
      assert {:error, :invalid_code} = Accounts.verify_otp(@phone, "000000")
      assert {:ok, player} = Accounts.verify_otp(@phone, code)
      assert player.phone == @phone
    end
  end
end
