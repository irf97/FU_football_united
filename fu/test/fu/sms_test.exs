defmodule Fu.SMSTest do
  @moduledoc "AUDIT #1 — SMS delivery is a pluggable adapter (real provider swappable)."
  use ExUnit.Case, async: false

  alias Fu.SMS

  defmodule TestAdapter do
    @behaviour Fu.SMS.Adapter
    @impl true
    def deliver(phone, body) do
      send(Application.fetch_env!(:fu, :sms_test_pid), {:sms, phone, body})
      :ok
    end
  end

  test "the default adapter is the log stub and returns :ok" do
    assert SMS.deliver("+31600000000", "hello") == :ok
  end

  test "deliver/2 routes to the configured adapter" do
    Application.put_env(:fu, :sms_test_pid, self())
    Application.put_env(:fu, Fu.SMS, adapter: TestAdapter)

    on_exit(fn ->
      Application.delete_env(:fu, Fu.SMS)
      Application.delete_env(:fu, :sms_test_pid)
    end)

    assert SMS.deliver("+31611112222", "code 123456") == :ok
    assert_receive {:sms, "+31611112222", "code 123456"}
  end
end
