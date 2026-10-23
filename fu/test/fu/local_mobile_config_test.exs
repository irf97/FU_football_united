defmodule Fu.LocalMobileConfigTest do
  use ExUnit.Case, async: true
  alias Fu.LocalMobileConfig

  defp settings(extra \\ %{}) do
    Map.merge(
      %{
        "FU_LOCAL_HOST" => "192.168.1.25",
        "FU_LOCAL_PUBLIC_PORT" => "4000",
        "DATABASE_URL" => "postgres://postgres:local-test@db:5432/spontaan_simulation",
        "SECRET_KEY_BASE" => String.duplicate("a", 96)
      },
      extra
    )
  end

  test "local networking has explicit origins and no public host fallback" do
    config = LocalMobileConfig.load!(settings())
    assert config.host == "192.168.1.25"
    assert config.port == 4000

    assert config.origins == [
             "http://192.168.1.25:4000",
             "http://localhost:4000",
             "http://127.0.0.1:4000"
           ]
  end

  test "private IPv4 and loopback hosts are accepted" do
    for host <- [
          "localhost",
          "127.0.0.1",
          "10.2.3.4",
          "172.16.0.2",
          "172.31.255.254",
          "192.168.10.2"
        ] do
      assert LocalMobileConfig.load!(settings(%{"FU_LOCAL_HOST" => host})).host == host
    end
  end

  test "public, unspecified, malformed and deceptive addresses are rejected" do
    for host <- [
          "0.0.0.0",
          "8.8.8.8",
          "172.15.0.1",
          "172.32.0.1",
          "192.169.0.1",
          "192.168.1.999",
          "192.168.01.1",
          "127.1",
          "::1",
          "example.com",
          "192.168.1.2.evil",
          "http://192.168.1.2",
          "192.168.1.2:4000",
          "192.168.1.2\n"
        ] do
      assert_raise ArgumentError, fn ->
        LocalMobileConfig.load!(settings(%{"FU_LOCAL_HOST" => host}))
      end
    end
  end

  test "the database must be isolated and local" do
    for url <- [
          "postgres://postgres:secret@db:5432/production",
          "postgres://postgres:secret@example.com/spontaan_simulation",
          "postgres://postgres:secret@db/spontaan_simulation?database=production",
          "postgres://postgres:secret@db/spontaan_simulation#other"
        ] do
      assert_raise ArgumentError, fn ->
        LocalMobileConfig.load!(settings(%{"DATABASE_URL" => url}))
      end
    end
  end

  test "missing secrets, missing settings and invalid ports stop startup" do
    for extra <- [
          %{"SECRET_KEY_BASE" => "short"},
          %{"SECRET_KEY_BASE" => ""},
          %{"FU_LOCAL_HOST" => ""},
          %{"FU_LOCAL_PUBLIC_PORT" => "80"},
          %{"FU_LOCAL_PUBLIC_PORT" => "65536"},
          %{"FU_LOCAL_PUBLIC_PORT" => "4000junk"}
        ] do
      assert_raise ArgumentError, fn -> LocalMobileConfig.load!(settings(extra)) end
    end
  end
end
