defmodule GovernanceCore.Protocols.FuzzTest do
  use ExUnit.Case
  use ExUnitProperties

  alias GovernanceCore.Protocols.ClawSpeak
  alias GovernanceCore.Protocols.UMP.Parser, as: UMPParser

  @moduledoc """
  Fuzzing tests for ClawSpeak and UMP protocols.
  """

  describe "ClawSpeak Protocol Fuzzing" do
    property "decode/1 handles random binary data without crashing" do
      check all binary <- binary() do
        result = ClawSpeak.decode(binary)
        assert match?({:ok, _, _} | {:error, _}, result)
      end
    end

    property "encode/1 and decode/1 roundtrip" do
      check all from <- byte(),
                to <- byte(),
                op <- byte(),
                arg <- binary(max_length: 255) do
        struct = %ClawSpeak{from: from, to: to, op: op, arg: arg}
        assert {:ok, encoded} = ClawSpeak.encode(struct)
        assert {:ok, decoded, <<>>} = ClawSpeak.decode(encoded)
        # We need to manually compare fields because the struct might have extra fields or defaults
        # But here we are constructing it explicitly.
        # The decoded struct will have the CRC calculated.
        assert decoded.from == from
        assert decoded.to == to
        assert decoded.op == op
        assert decoded.arg == arg
      end
    end
  end

  describe "UMP Parser Fuzzing" do
    property "parse_frame/1 handles random binary data without crashing" do
      check all binary <- binary() do
        result = UMPParser.parse_frame(binary)
        assert match?({:ok, _} | {:error, _}, result)
      end
    end

    property "parse_frame/1 handles valid-looking frames" do
      check all from <- byte(),
                to <- byte(),
                op <- member_of([0x10, 0x11, 0x12, 0x20, 0x21, 0x22, 0x30, 0x31, 0x40]),
                rest <- binary() do
        # Construct a potentially valid frame
        frame = <<from::8, to::8, op::8, rest::binary>>
        result = UMPParser.parse_frame(frame)

        # We expect either a successful parse (if rest matches the op's requirements)
        # or an error (malformed payload, invalid format, etc.)
        # The key is that it shouldn't raise an exception.
        assert match?({:ok, _} | {:error, _}, result)
      end
    end
  end
end
