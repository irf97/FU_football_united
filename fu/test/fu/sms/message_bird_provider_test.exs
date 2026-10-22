defmodule Fu.SMS.MessageBirdProviderTest do
  use ExUnit.Case, async: true
  alias Fu.SMS.MessageBirdProvider, as: Provider

  test "builds the documented SMS protocol without coupling accounts to a vendor" do
    req =
      Provider.build("+31680000001", "Your FU code is 123456",
        api_key: "placeholder",
        originator: "FU"
      )

    assert req.method == :post
    assert req.url == "https://rest.messagebird.com/messages"
    assert {"authorization", "AccessKey placeholder"} in req.headers

    assert URI.decode_query(req.body) == %{
             "originator" => "FU",
             "recipients" => "+31680000001",
             "body" => "Your FU code is 123456"
           }
  end

  test "a valid acceptance receipt is required even for a successful HTTP status" do
    assert Provider.handle(201, ~s({"id":"sms-1","recipients":{"totalCount":1}})) == :ok
    assert Provider.handle(201, "not-json") == {:error, :invalid_response}
    assert Provider.handle(200, ~s({"errors":[]})) == {:error, :invalid_response}
  end

  test "provider failures are classified without reflecting sensitive response bodies" do
    assert Provider.handle(429, "private-provider-response") == {:error, :rate_limited}
    assert Provider.handle(401, "secret-token") == {:error, :unauthorized}
    assert Provider.handle(500, "private-provider-response") == {:error, :provider_unavailable}
  end
end
