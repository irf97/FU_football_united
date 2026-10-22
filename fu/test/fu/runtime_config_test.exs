defmodule Fu.RuntimeConfigTest do
  use ExUnit.Case, async: true
  alias Fu.RuntimeConfig

  defp rehearsal(extra \\ %{}) do
    Map.merge(
      %{
        "FU_MODE" => "rehearsal",
        "PHX_HOST" => "localhost",
        "FU_SMS_PROVIDER" => "messagebird",
        "FU_SMS_API_KEY" => "fu-sim-test-only",
        "FU_SMS_ENDPOINT" => "http://sms:9166/messages",
        "FU_SMS_ORIGINATOR" => "FU"
      },
      extra
    )
  end

  test "production defaults to disabled delivery, never a log adapter" do
    profile = RuntimeConfig.load(%{})
    assert profile.environment == :production
    assert profile.sms == [adapter: Fu.SMS.HTTPAdapter]
  end

  test "a live MessageBird account uses the same adapter and a fixed HTTPS endpoint" do
    profile =
      RuntimeConfig.load(%{
        "FU_SMS_PROVIDER" => "messagebird",
        "FU_SMS_API_KEY" => "live-test-placeholder",
        "FU_SMS_ORIGINATOR" => "FU"
      })

    assert profile.environment == :production
    assert profile.sms[:provider] == Fu.SMS.MessageBirdProvider
    assert profile.sms[:transport] == Fu.SMS.ReqTransport
    assert profile.sms[:config][:endpoint] == "https://rest.messagebird.com/messages"
  end

  test "rehearsal uses a labelled local provider endpoint" do
    profile = RuntimeConfig.load(rehearsal())
    assert profile.environment == :rehearsal
    assert profile.sms[:provider] == Fu.SMS.MessageBirdProvider
    assert profile.sms[:config][:endpoint] == "http://sms:9166/messages"
  end

  test "production rejects simulator endpoints and simulator credentials" do
    assert_raise ArgumentError, fn ->
      RuntimeConfig.load(%{"FU_SMS_ENDPOINT" => "http://sms:9166/messages"})
    end

    assert_raise ArgumentError, fn ->
      RuntimeConfig.load(%{
        "FU_SMS_PROVIDER" => "messagebird",
        "FU_SMS_API_KEY" => "fu-sim-test-only",
        "FU_SMS_ORIGINATOR" => "FU"
      })
    end
  end

  test "rehearsal rejects public app hosts, public SMS endpoints and live credentials" do
    for extra <- [
          %{"PHX_HOST" => "example.com"},
          %{"FU_SMS_ENDPOINT" => "https://rest.messagebird.com/messages"},
          %{"FU_SMS_API_KEY" => "live-test-placeholder"}
        ] do
      assert_raise ArgumentError, fn -> RuntimeConfig.load(rehearsal(extra)) end
    end
  end

  test "missing credentials and unknown modes or providers fail at startup" do
    for env <- [
          %{"FU_MODE" => "pretend-production"},
          %{"FU_SMS_PROVIDER" => "unknown"},
          %{"FU_SMS_PROVIDER" => "messagebird"}
        ] do
      assert_raise ArgumentError, fn -> RuntimeConfig.load(env) end
    end
  end
end
