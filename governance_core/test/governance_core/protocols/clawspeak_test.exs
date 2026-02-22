defmodule GovernanceCore.Protocols.ClawSpeakTest do
  use ExUnit.Case, async: true
  alias GovernanceCore.Protocols.ClawSpeak

  test "encodes and decodes a valid frame" do
    frame = %ClawSpeak{from: 1, to: 2, op: 10, arg: "hello"}
    assert {:ok, binary} = ClawSpeak.encode(frame)

    assert {:ok, decoded, <<>>} = ClawSpeak.decode(binary)
    assert decoded.from == 1
    assert decoded.to == 2
    assert decoded.op == 10
    assert decoded.arg == "hello"
    assert decoded.crc == :erlang.crc32(<<1, 2, 10, 5, "hello">>)
  end

  test "detects crc mismatch" do
    payload = <<1, 2, 10, 5, "hello">>
    bad_crc = 12345
    binary = <<payload::binary, bad_crc::32>>

    assert {:error, :crc_mismatch} = ClawSpeak.decode(binary)
  end

  test "handles incomplete frame" do
    assert {:error, :incomplete_frame} = ClawSpeak.decode(<<1, 2>>)
  end

  test "rejects arguments longer than 255 bytes" do
    long_arg = String.duplicate("a", 256)
    frame = %ClawSpeak{from: 1, to: 2, op: 10, arg: long_arg}
    assert {:error, :arg_too_long} = ClawSpeak.encode(frame)
  end
end
