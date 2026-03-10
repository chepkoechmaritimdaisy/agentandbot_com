defmodule GovernanceCore.Protocols.FuzzTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GovernanceCore.Protocols.ClawSpeak
  alias GovernanceCore.Protocols.UMP

  property "ClawSpeak.decode/1 handles random binary data without crashing" do
    check all bin <- StreamData.binary() do
      try do
        case ClawSpeak.decode(bin) do
          {:ok, %ClawSpeak{}, _rest} -> :ok
          {:error, _reason} -> :ok
          unexpected ->
            flunk("Unexpected return from ClawSpeak.decode/1: #{inspect(unexpected)}")
        end
      rescue
        e -> flunk("ClawSpeak.decode/1 crashed with exception: #{inspect(e)}")
      catch
        kind, value -> flunk("ClawSpeak.decode/1 crashed with #{kind}: #{inspect(value)}")
      end
    end
  end

  property "UMP.parse/1 handles random binary data without crashing" do
    check all bin <- StreamData.binary() do
      try do
        case UMP.parse(bin) do
          {:ok, _data} -> :ok
          {:error, _reason} -> :ok
          unexpected ->
            flunk("Unexpected return from UMP.parse/1: #{inspect(unexpected)}")
        end
      rescue
        e -> flunk("UMP.parse/1 crashed with exception: #{inspect(e)}")
      catch
        kind, value -> flunk("UMP.parse/1 crashed with #{kind}: #{inspect(value)}")
      end
    end
  end
end
