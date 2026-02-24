defmodule GovernanceCore.Protocols.ClawSpeakFuzzTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GovernanceCore.Protocols.ClawSpeak
  alias GovernanceCore.Protocols.UMP.Parser, as: UMPParser

  @moduletag :property

  describe "ClawSpeak Fuzzing" do
    property "encode/decode roundtrip is consistent" do
      check all(
        from <- integer(0..255),
        to <- integer(0..255),
        op <- integer(0..255),
        arg <- binary(max_length: 255)
      ) do
        frame = %ClawSpeak{from: from, to: to, op: op, arg: arg}
        assert {:ok, encoded} = ClawSpeak.encode(frame)
        assert {:ok, decoded, <<>>} = ClawSpeak.decode(encoded)
        # Check equality ignoring the computed CRC field in the comparison if needed,
        # but ClawSpeak.decode populates it, so we should match.
        assert decoded.from == frame.from
        assert decoded.to == frame.to
        assert decoded.op == frame.op
        assert decoded.arg == frame.arg
      end
    end

    property "decode handles random binary garbage without crashing" do
      check all(binary <- binary()) do
        result = ClawSpeak.decode(binary)
        assert match?({:ok, _, _} | {:error, _}, result)
      end
    end
  end

  describe "UMP Parser Fuzzing" do
    property "parse_frame handles random binary garbage without crashing" do
      check all(binary <- binary()) do
        result = UMPParser.parse_frame(binary)
        assert match?({:ok, _} | {:error, _}, result)
      end
    end

    property "parse_frame correctly identifies valid structures" do
      check all(
        from <- integer(0..255),
        to <- integer(0..255),
        # Testing specific opcodes known to UMPParser
        op <- member_of([0x10, 0x11, 0x12, 0x20, 0x21, 0x22, 0x30, 0x31, 0x40]),
        id <- integer(0..255),
        hash <- integer(0..4294967295)
      ) do
        # Construct valid frames manually based on UMPParser logic
        binary = case op do
          o when o in [0x10, 0x11, 0x20, 0x21, 0x30, 0x31] ->
            <<from, to, op, id>>
          o when o in [0x12, 0x22] ->
            <<from, to, op, id, hash::32>>
          0x40 ->
             <<from, to, op, id>> # id here is new_id
          _ -> <<>>
        end

        if binary != <<>> do
          assert {:ok, result} = UMPParser.parse_frame(binary)
          assert result.from == from
          assert result.to == to
        end
      end
    end
  end
end
