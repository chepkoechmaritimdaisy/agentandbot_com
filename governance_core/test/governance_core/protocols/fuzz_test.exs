defmodule GovernanceCore.Protocols.FuzzTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GovernanceCore.Protocols.ClawSpeak
  alias GovernanceCore.Protocols.UMP.Parser, as: UMPParser
  alias GovernanceCore.Protocols.UMP

  property "ClawSpeak decode does not crash with random binaries" do
    check all bin <- binary() do
      try do
        _ = ClawSpeak.decode(bin)
      rescue
        _e -> flunk("ClawSpeak.decode crashed with input: #{inspect(bin)}")
      end
    end
  end

  property "UMP.Parser parse_frame does not crash with random binaries" do
    check all bin <- binary() do
      try do
        _ = UMPParser.parse_frame(bin)
      rescue
        _e -> flunk("UMPParser.parse_frame crashed with input: #{inspect(bin)}")
      end
    end
  end

  property "UMP parse does not crash with random binaries" do
    check all bin <- binary() do
      try do
        _ = UMP.parse(bin)
      rescue
        _e -> flunk("UMP.parse crashed with input: #{inspect(bin)}")
      end
    end
  end
end
