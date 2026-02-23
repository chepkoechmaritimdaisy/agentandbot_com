defmodule GovernanceCore.Protocols.ClawSpeakFuzzTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GovernanceCore.Protocols.ClawSpeak

  @moduledoc """
  Fuzzing tests for ClawSpeak protocol to ensure robustness against random binary inputs
  and consistency in encoding/decoding.
  """

  property "decode/1 never crashes with random binary data" do
    check all binary <- binary() do
      case ClawSpeak.decode(binary) do
        {:ok, _, _} -> assert true
        {:error, _} -> assert true
        result -> flunk("Unexpected return: #{inspect(result)}")
      end
    end
  end

  property "roundtrip encoding/decoding preserves data" do
    check all from <- integer(0..255),
              to <- integer(0..255),
              op <- integer(0..255),
              # Arg length is limited to 255 bytes by the protocol (8-bit length field)
              arg <- binary(max_length: 255) do
      original_struct = %ClawSpeak{from: from, to: to, op: op, arg: arg}

      assert {:ok, encoded_binary} = ClawSpeak.encode(original_struct)
      assert {:ok, decoded_struct, <<>>} = ClawSpeak.decode(encoded_binary)

      # We don't check CRC in the struct equality because it's calculated on encode
      # but the decoded struct includes it.
      assert decoded_struct.from == original_struct.from
      assert decoded_struct.to == original_struct.to
      assert decoded_struct.op == original_struct.op
      assert decoded_struct.arg == original_struct.arg
    end
  end

  property "encode/1 rejects args longer than 255 bytes" do
    check all arg <- binary(min_length: 256) do
      struct = %ClawSpeak{from: 1, to: 2, op: 3, arg: arg}
      assert {:error, :arg_too_long} = ClawSpeak.encode(struct)
    end
  end
end
