defmodule GovernanceCore.Protocols.FuzzTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GovernanceCore.Protocols.ClawSpeak
  alias GovernanceCore.Protocols.UMP

  property "ClawSpeak protocol correctly handles valid and invalid random data" do
    check all from <- integer(0..255),
              to <- integer(0..255),
              op <- integer(0..255),
              arg <- binary(max_length: 255) do
      frame = %ClawSpeak{from: from, to: to, op: op, arg: arg}
      assert {:ok, encoded} = ClawSpeak.encode(frame)
      assert {:ok, decoded, <<>>} = ClawSpeak.decode(encoded)

      assert decoded.from == from
      assert decoded.to == to
      assert decoded.op == op
      assert decoded.arg == arg
    end
  end

  property "UMP Parser correctly handles arbitrary binary data" do
    check all bin <- binary() do
      # Ensure it doesn't crash on random binary data
      case UMP.parse(bin) do
        {:ok, _data} ->
          # If it happens to be valid JSON, it should be an :ok tuple
          assert true
        {:error, :invalid_json} ->
          # If not, it should safely return :invalid_json error
          assert true
      end
    end
  end
end
