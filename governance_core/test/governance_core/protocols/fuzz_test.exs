defmodule GovernanceCore.Protocols.FuzzTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GovernanceCore.Protocols.ClawSpeak
  alias GovernanceCore.Protocols.UMP

  describe "ClawSpeak fuzzing" do
    property "decode/1 safely handles any random binary payload" do
      check all(binary_payload <- binary()) do
        result = ClawSpeak.decode(binary_payload)

        # The function should either return {:ok, struct, rest} or an {:error, reason}
        # It must never crash or raise an exception
        assert match?({:ok, %ClawSpeak{}, _}, result) or match?({:error, _}, result)
      end
    end

    property "encode/1 and decode/1 are symmetric for valid args" do
      check all(
              from <- integer(0..255),
              to <- integer(0..255),
              op <- integer(0..255),
              arg <- string(:ascii, max_length: 255)
            ) do
        struct = %ClawSpeak{from: from, to: to, op: op, arg: arg}

        case ClawSpeak.encode(struct) do
          {:ok, encoded} ->
            assert {:ok, decoded, <<>>} = ClawSpeak.decode(encoded)
            assert decoded.from == struct.from
            assert decoded.to == struct.to
            assert decoded.op == struct.op
            assert decoded.arg == struct.arg
          {:error, _reason} ->
            # Only happens if arg > 255 bytes, but we limited it in the generator
            flunk("Failed to encode a valid struct")
        end
      end
    end
  end

  describe "UMP fuzzing" do
    property "parse/1 safely handles any random binary string" do
      check all(payload <- binary()) do
        result = UMP.parse(payload)

        assert match?({:ok, _}, result) or match?({:error, :invalid_json}, result)
      end
    end
  end
end
