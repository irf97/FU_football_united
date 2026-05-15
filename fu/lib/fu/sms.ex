defmodule Fu.SMS do
  @moduledoc """
  SMS delivery stub (spec §5: "API stubs"). v1 logs the message instead of
  sending. Swap the body for a Twilio/MessageBird client later.
  """
  require Logger

  def deliver(phone, body) do
    Logger.info("[SMS→#{phone}] #{body}")
    :ok
  end
end
