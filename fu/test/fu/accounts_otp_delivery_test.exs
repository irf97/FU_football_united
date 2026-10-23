defmodule Fu.AccountsOtpDeliveryTest do
  use Fu.DataCase, async: false
  alias Fu.Accounts
  alias Fu.Accounts.OtpCode

  defmodule FailedDelivery do
    @behaviour Fu.SMS.Adapter
    def deliver(_, _), do: {:error, :timeout}
  end

  setup do
    previous = Application.fetch_env(:fu, Fu.SMS)
    Application.put_env(:fu, Fu.SMS, adapter: FailedDelivery)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:fu, Fu.SMS, value)
        :error -> Application.delete_env(:fu, Fu.SMS)
      end
    end)
  end

  test "failed delivery is reported, burns the code and still counts against the request cap" do
    phone = "+31680000001"
    assert {:error, :delivery_failed} = Accounts.request_otp(phone)
    otp = Repo.one!(from(o in OtpCode, where: o.phone == ^phone))
    assert otp.consumed_at
    assert {:error, :invalid_code} = Accounts.verify_otp(phone, otp.code)
    for _ <- 1..4, do: assert({:error, :delivery_failed} = Accounts.request_otp(phone))
    assert {:error, :rate_limited} = Accounts.request_otp(phone)
  end

  test "invalid phone input allocates no OTP and makes no delivery attempt" do
    assert {:error, :invalid_phone} = Accounts.request_otp("not a phone")
    assert Repo.aggregate(OtpCode, :count) == 0
  end
end
