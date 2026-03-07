defmodule GovernanceCore.Protocols.FuzzTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GovernanceCore.Protocols.ClawSpeak
  alias GovernanceCore.Protocols.UMP.Parser

  describe "ClawSpeak Fuzzing" do
    property "does not crash on random binary input for decode/1" do
      check all bin <- binary() do
        result = ClawSpeak.decode(bin)
        assert match?({:ok, _, _}, result) or match?({:error, _}, result)
      end
    end
  end

  describe "UMP Fuzzing" do
    property "does not crash on random binary input for parse_frame/1" do
      check all bin <- binary() do
        result = Parser.parse_frame(bin)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end
  end
end
