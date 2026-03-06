defmodule GovernanceCore.Protocols.FuzzTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GovernanceCore.Protocols.ClawSpeak
  alias GovernanceCore.Protocols.UMP.Parser

  property "ClawSpeak.decode/1 never crashes with random binary data" do
    check all data <- binary() do
      try do
        result = ClawSpeak.decode(data)
        case result do
          {:ok, _, _rest} -> true
          {:error, _reason} -> true
          _ -> flunk("Expected {:ok, _, _} or {:error, _}, got #{inspect(result)}")
        end
      rescue
        e -> flunk("ClawSpeak.decode/1 crashed with #{inspect(e)} on input #{inspect(data)}")
      end
    end
  end

  property "UMP.Parser.parse_frame/1 never crashes with random binary data" do
    check all data <- binary() do
      try do
        result = Parser.parse_frame(data)
        case result do
          {:ok, _} -> true
          {:error, _reason} -> true
          _ -> flunk("Expected {:ok, _} or {:error, _}, got #{inspect(result)}")
        end
      rescue
        e -> flunk("UMP.Parser.parse_frame/1 crashed with #{inspect(e)} on input #{inspect(data)}")
      end
    end
  end
end
