defmodule GovernanceCore.Protocols.FuzzTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GovernanceCore.Protocols.ClawSpeak
  alias GovernanceCore.Protocols.UMP

  property "fuzzes ClawSpeak protocol frames without crashing" do
    check all(
            from <- integer(0..255),
            to <- integer(0..255),
            op <- integer(0..255),
            arg <- binary()
          ) do
      # Test encoding logic
      case ClawSpeak.encode(%ClawSpeak{from: from, to: to, op: op, arg: arg}) do
        {:ok, encoded_frame} ->
          # Test decoding logic
          case ClawSpeak.decode(encoded_frame) do
            {:ok, decoded, _rest} ->
              assert decoded.from == from
              assert decoded.to == to
              assert decoded.op == op
              assert decoded.arg == arg
            {:error, _reason} ->
              # Allowed to fail but not crash
              :ok
          end

        {:error, :arg_too_long} ->
          # Valid expected error
          assert byte_size(arg) > 255
      end
    end
  end

  property "fuzzes UMP payload parsing without crashing" do
    check all(payload <- binary()) do
      # Ensure it parses or correctly rejects invalid payload without raising
      case UMP.parse(payload) do
        {:ok, _data} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end
end
