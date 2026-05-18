defmodule Fu.PositionsTest do
  @moduledoc "Rated-format contract (spec §2.11 + user decision: 8v8 AND 7v7 rated)."
  use ExUnit.Case, async: true

  alias Fu.Positions

  describe "rated?/1" do
    test "8v8 is rated" do
      assert Positions.rated?("8v8")
    end

    test "7v7 is rated (user decision 2026-05-17)" do
      assert Positions.rated?("7v7")
    end

    test "every other format is unrated" do
      for f <- ~w(5v5 6v6 9v9 11v11) do
        refute Positions.rated?(f), "#{f} must not be rated"
      end
    end
  end
end
